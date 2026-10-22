#!/bin/bash

# ==============================================================================
# Filename:         wireshark.sh
# Description:      Pipe tcpdump over ssh into wireshark
# Author:           Adam A https://github.com/atariq11700
# Date Created:     2026-8-6
# License:          AGPL-3.0
# ==============================================================================

set -o pipefail

trap 'exit 130' INT TERM

log() { echo "[swireshark] $*" >&2; }
die() { log "ERROR: $*"; exit 1; }

usage() {
    cat <<'EOF'
Usage: swireshark.sh <host> <iface> [-n <namespace>] [-p <profile>] [-h]

Pipe a remote tcpdump capture into a local Wireshark instance.

Note: All preferences changed in this session will not save.

Arguments:
  host              Remote SSH host (user@host or alias from ~/.ssh/config).
  iface             Network interface to capture on.

Options:
  -n <namespace>    Linux network namespace to run in (default: GLOBAL).
  -p <profile>      The base profile to start from.
  -h                Show this help message and exit.
EOF
}

# Arg parsing
ns=""
positionals=()
profile=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        -n) ns="$2"; shift 2 ;;
        -p) profile="$2"; shift 2 ;;
        -h) usage; exit 0 ;;
        --) shift; positionals+=("$@"); break ;;
        -*) usage; exit 1 ;;
        *)  positionals+=("$1"); shift ;;
    esac
done

host="${positionals[0]}"
iface="${positionals[1]}"

if [[ -z "$host" || -z "$iface" ]]; then
    usage; exit 1
fi

ns_label="${ns:-GLOBAL}"
ns_exec="${ns:+/sbin/ip netns exec ${ns} }"

# Suppress SSH connection-stats banners; still surface real errors.
SSH_OPTS=(-o LogLevel=ERROR)

log "Host:      $host"
log "Interface: $iface"
log "Namespace: $ns_label"

# Locate tcpdump on the remote host
tcpdump_path=""
for candidate in /usr/sbin/tcpdump /usr/bin/tcpdump; do
    if ssh "${SSH_OPTS[@]}" "$host" "test -x $candidate"; then
        tcpdump_path="$candidate"
        break
    fi
done
[[ -n "$tcpdump_path" ]] || die "tcpdump not found on $host"
log "Tcpdump:   $tcpdump_path"

# Show interface info
[[ "$iface" != "any" ]] && log "--- ifconfig $iface ---"
if [[ "$iface" == "any" ]] || ! ssh "${SSH_OPTS[@]}" "$host" "${ns_exec}/sbin/ifconfig ${iface}"; then
    log "--- ifconfig (all devices) ---"
    ssh "${SSH_OPTS[@]}" "$host" "${ns_exec}/sbin/ifconfig" || true
    [[ "$iface" != "any" ]] && die "interface ${iface} not found on ${host}"
fi

folders=$(tshark -G folders)
pconf_folder=$(sed -n 's/^Personal configuration:[[:space:]]*//p' <<<"$folders" | tr -d '\r')
[[ -n "$pconf_folder" ]] || die "personal configuration folder not found"
log "Personal Configuration Folder: $pconf_folder"

tmpdir=$(mktemp -d) || die "cannot create temp dir"
trap '[[ -n $tmpdir ]] && log "Deleting Tmp Configuration Folder: $tmpdir" && rm -rf "${tmpdir:?}"' EXIT
log "Tmp Configuration Folder: $tmpdir"

for f in "$pconf_folder"/*; do
    [[ -f "$f" ]] && cp -p "$f" "$tmpdir/"
    log "Copied $f -> $tmpdir"
done

if [[ -n "$profile" && -d "$pconf_folder/profiles/$profile" ]]; then
    mkdir -p "$tmpdir/profiles"
    cp -rp "$pconf_folder/profiles/$profile" "$tmpdir/profiles/"
    log "Copied -r $pconf_folder/profiles/$profile -> $tmpdir/profiles/"
fi

ws_tmpdir="$tmpdir"
if command -v cygpath >/dev/null; then
    ws_tmpdir=$(cygpath -w "$tmpdir");
    log "$tmpdir -> $ws_tmpdir"
fi

ws_args=(-k -P "persconf:${ws_tmpdir}" -o "gui.window_title:${host} (${ns_label}): ${iface}" -Y "not (tcp.port == 22)")
if [[ -n "$profile" ]]; then ws_args+=(-C "$profile"); fi
log "Wireshark Args: ${ws_args[@]}"

# Run the capture pipeline
remote_capture="${ns_exec}${tcpdump_path} -i ${iface} -U -s0 -w -"
log "Capture Command: $remote_capture"
log "--- Starting capture ---"

# A pipeline would wait on ssh after Wireshark closes; feed stdin from a process substitution instead.
wireshark "${ws_args[@]}" -i - < <(ssh "${SSH_OPTS[@]}" "$host" "$remote_capture")
ssh_pid=$!
kill "$ssh_pid" 2>/dev/null || true

#!/bin/bash

# ==============================================================================
# Filename:         submoduletags.sh
# Description:      Recursively crawl a git repository, fetch each submodule, and
#                   print the tags that point at each submodule's currently
#                   checked-out commit, sorted alphabetically.
# Author:           Adam A https://github.com/atariq11700
# Date Created:     2026-10-21
# License:          AGPL-3.0
# ==============================================================================

set -o pipefail

#---------------------------------------------------------------------
# Argparsing
#---------------------------------------------------------------------

usage() {
    cat <<EOF
Usage: $(basename "$0") [-h] [-r] [-l] [-t] [-P] [-c] [-d depth] [-v] [-p prefix] [repo_path]

Recursively crawl a git repo, fetch each submodule, and print all tags
at each submodule's currently checked-out commit (sorted alphabetically).

Arguments:
  repo_path   Path to the git repository to crawl (default: current dir).

Options:
  -r          Sort tags in reverse alphabetical order.
  -l          Show the parent-repo commits that changed this submodule's
              pinned commit (when the pointer last moved) instead of tags.
  -t          In log mode, also annotate commits with parent-repo tags
              (slower). Tags on an update commit follow a |; in-between
              commits appear on dash-prefixed lines (consecutive single-tag
              commits are joined with |). Implies -l.
  -P          Porcelain output: stable tab-separated records for scripts
              (one record per line, no aggregation). Record types below.
  -c          Colorize output (needs a 256-color terminal; ignored with -P).
  -d depth    In log mode (-l), limit the updates shown. Either an integer
              N (last N updates; -1 for all) or a parent-repo commit/tag to
              show updates since (and including) that ref. Default: 10.
  -p prefix   Only check submodules whose path starts with 'prefix'.
  -v          Print git warnings/errors verbosely (default: off).
  -h          Show this help message and exit.

Porcelain (-P) emits tab-separated records, one per line:
  sub      <path> <sha> <status>          always, first for each submodule
  tag      <path> <tag>                    default mode (current-commit tag)
  commit   <path> <sha> <subject>          -l
  update   <path> <sha> <subject> <tags>   -l -t: the update commit
  between  <path> <sha> <tags>             -l -t: an in-between tagged commit
EOF
}

# getopts setup
OPTIND=1

# Option defaults
REVERSE=""
PREFIX=""
VERBOSE=""
LOG=""
TAGS=""
PORCELAIN=""
COLOR=""
DEPTH=10

while getopts "hrltPcd:vp:" opt; do
    case "${opt}" in
        r)
            REVERSE=1
            ;;
        l)
            LOG=1
            ;;
        t)
            TAGS=1
            LOG=1
            ;;
        P)
            PORCELAIN=1
            ;;
        c)
            COLOR=1
            ;;
        d)
            DEPTH=${OPTARG}
            ;;
        p)
            PREFIX=${OPTARG}
            ;;
        v)
            VERBOSE=1
            ;;
        h)
            usage
            exit 0
            ;;
        *)
            usage
            exit 1
            ;;
    esac
done
shift $((OPTIND-1))

# Repo path (default to current working directory)
REPO_PATH="${1:-$PWD}"

#---------------------------------------------------------------------
# Validation
#---------------------------------------------------------------------

if [[ ! -d "$REPO_PATH" ]]; then
    echo "Error: '$REPO_PATH' is not a directory" >&2
    exit 1
fi

if ! git -C "$REPO_PATH" rev-parse --is-inside-work-tree > /dev/null 2>&1; then
    echo "Error: '$REPO_PATH' is not a git repository" >&2
    exit 1
fi

# The depth is either a positive integer (last N updates), -1 (all), or a
# parent-repo commit/tag to show updates since (and including) that ref.
DEPTH_REF=""
if printf "%s" "$DEPTH" | grep -Eq "^(-1|[0-9]+)$"; then
    :
elif git -C "$REPO_PATH" rev-parse --verify --quiet "${DEPTH}^{commit}" >/dev/null 2>&1; then
    DEPTH_REF="$DEPTH"
else
    echo "Error: -d must be an integer, -1, or a known commit/tag (got '$DEPTH')" >&2
    exit 1
fi

#---------------------------------------------------------------------
# Crawl submodules
#---------------------------------------------------------------------

# awk program used by log+tags mode (-t) to turn a git log range into output
# lines. Kept out of the foreach body (which cannot contain single quotes) and
# passed in via the environment. Input fields are 0x1f-separated:
#   $1 = short sha, $2 = subject, $3 = ref decorations.
# Variables: REV=1 reverses tag sort; P=displaypath; MODE=1 selects porcelain
# (tab-separated "update"/"between" records), otherwise pretty output where the
# first record is the update commit (tags follow a | ) and later records are
# in-between commits (consecutive single-tag commits combined on one dash line,
# multi-tag commits kept on their own line). CSHA/CTAG/CDASH/CRST hold ANSI
# color codes (empty when color is off).
ST_AWK=$(cat <<'AWK'
function flush() {
    if (pend != "") { print CDASH dashbar CRST " " pend; pend = "" }
}
BEGIN { FS = sprintf("%c", 31); pend = ""; dashbar = "-" }
{
    split("", tg)
    ntags = split($3, refs, ",")
    tc = 0
    for (i = 1; i <= ntags; i++) {
        r = refs[i]
        sub(/^ +/, "", r)
        if (substr(r, 1, 5) == "tag: ") { tc++; tg[tc] = substr(r, 6) }
    }
    for (i = 2; i <= tc; i++) {
        key = tg[i]; j = i - 1
        while (j >= 1 && ((REV == "1") ? (tg[j] < key) : (tg[j] > key))) { tg[j+1] = tg[j]; j-- }
        tg[j+1] = key
    }
    joined = ""
    for (i = 1; i <= tc; i++) joined = joined (i > 1 ? " " : "") tg[i]

    # Porcelain: stable tab-separated records, one commit per line.
    if (MODE == "1") {
        if (NR == 1) print "update\t" P "\t" $1 "\t" $2 "\t" joined
        else if (tc > 0) print "between\t" P "\t" $1 "\t" joined
        next
    }

    # First record is the submodule update commit itself. Remember the short
    # sha width so in-between dash lines can be padded to align tags under the
    # subject column.
    if (NR == 1) {
        dashbar = ""
        while (length(dashbar) < length($1)) dashbar = dashbar "-"
        if (tc > 0) print CSHA $1 CRST " " $2 " | " CTAG joined CRST
        else print CSHA $1 CRST " " $2
        next
    }

    # In-between commits: aggregate consecutive single-tag commits onto one
    # dash line joined by | , but keep any multi-tag commit on its own line.
    if (tc == 0) next
    if (tc == 1) {
        pend = (pend == "" ? (CTAG tg[1] CRST) : pend " | " CTAG tg[1] CRST)
    } else {
        flush()
        print CDASH dashbar CRST " " CTAG joined CRST
    }
}
END { flush() }
AWK
)

# ANSI colors for -c (color) mode. Uses 256-color codes so the hues stay
# distinct. Disabled in porcelain mode so -P stays a clean, machine-parseable
# stream. Empty strings when color is off, so the same code paths produce
# uncolored output.
if [ -n "$COLOR" ] && [ -z "$PORCELAIN" ]; then
    C_ARROW=$(printf '\033[1;38;5;208m')  # ===> : bold orange
    C_PATH=$(printf '\033[38;5;39m')      # submodule path : blue
    C_SHA=$(printf '\033[38;5;76m')       # sha1 / sha256 : green
    C_TAG=$(printf '\033[38;5;180m')      # tags : warm tan
    C_DASH=$(printf '\033[38;5;201m')     # in-between dash : magenta
    C_WARN=$(printf '\033[38;5;226m')     # warning : yellow
    C_ERR=$(printf '\033[38;5;196m')      # error : red
    C_RST=$(printf '\033[0m')
else
    C_ARROW=""; C_PATH=""; C_SHA=""; C_TAG=""; C_DASH=""; C_WARN=""; C_ERR=""; C_RST=""
fi
export C_ARROW C_PATH C_SHA C_TAG C_DASH C_WARN C_ERR C_RST

# Pass options into the foreach body via the environment. git submodule
# foreach runs the body in a separate POSIX sh, so the vars must be exported.
export ST_REVERSE="$REVERSE"
export ST_PREFIX="$PREFIX"
export ST_VERBOSE="$VERBOSE"
export ST_LOG="$LOG"
export ST_TAGS="$TAGS"
export ST_PORCELAIN="$PORCELAIN"
export ST_DEPTH="$DEPTH"
export ST_DEPTH_REF="$DEPTH_REF"
export ST_AWK

# git submodule foreach --recursive descends into nested submodules and
# exposes $displaypath (path relative to the top-level repo) for each one.
# NOTE: foreach runs this body with POSIX sh, so use portable syntax only
# (e.g. [ ] instead of [[ ]]).
git -C "$REPO_PATH" submodule foreach --quiet --recursive '
    # Restrict to submodules under the requested path prefix (if any).
    case "$displaypath" in
        "$ST_PREFIX"*) : ;;
        *) exit 0 ;;
    esac

    # Fetch remote refs (including tags); capture stderr and the exit status.
    fetch_err=$(git fetch --tags --quiet 2>&1 1>/dev/null)
    fetch_rc=$?

    if [ -n "$ST_LOG" ]; then
        # Parent-repo commits that changed the submodule pinned commit, so you
        # can see when the submodule pointer was last updated. ST_DEPTH limits
        # how many updates to show (-1 means show all). $toplevel is the
        # immediate superproject and $sm_path is the submodule path within it.
        # Resolve the depth into git log selection args. A numeric depth uses a
        # max-count; a ref (ST_DEPTH_REF) selects the range since (including)
        # that commit/tag in this superproject; -1 shows all.
        ref_commit=""
        lower=""
        if [ -n "$ST_DEPTH_REF" ]; then
            ref_commit=$(git -C "$toplevel" rev-parse --verify --quiet "${ST_DEPTH_REF}^{commit}" 2>/dev/null)
            [ -n "$ref_commit" ] && lower=$(git -C "$toplevel" rev-parse --verify --quiet "${ref_commit}~1" 2>/dev/null)
        fi

        if [ -n "$ST_DEPTH_REF" ]; then
            # Show updates since (and including) the ref. When the ref is a root
            # commit or is not present in this superproject, show everything.
            if [ -n "$lower" ]; then
                fast_sel="$lower..HEAD"
                list_sel="$lower..HEAD"
            else
                fast_sel=""
                list_sel=""
            fi
            show_n="-1"
            final_lower="$lower"
        elif [ "$ST_DEPTH" = "-1" ]; then
            fast_sel=""
            list_sel=""
            show_n="-1"
            final_lower=""
        else
            # One extra commit gives the last shown one a lower boundary.
            fast_sel="-$ST_DEPTH"
            list_sel="-$((ST_DEPTH + 1))"
            show_n="$ST_DEPTH"
            final_lower=""
        fi

        if [ -z "$ST_TAGS" ]; then
            # Fast path: just the commits that moved the submodule pointer.
            US=$(printf "\037")
            if [ -n "$ST_PORCELAIN" ]; then
                body=$(git -C "$toplevel" log $fast_sel --format="%h%x1f%s" -- "$sm_path" 2>/dev/null |
                    while IFS="$US" read -r csha csubj; do
                        printf "commit\t%s\t%s\t%s\n" "$displaypath" "$csha" "$csubj"
                    done)
            else
                body=$(git -C "$toplevel" log $fast_sel --format="%h%x1f%s" -- "$sm_path" 2>/dev/null |
                    while IFS="$US" read -r csha csubj; do
                        printf "%s%s%s %s\n" "$C_SHA" "$csha" "$C_RST" "$csubj"
                    done)
            fi
        else
            # Annotated path (slower, enabled by -t): also show parent-repo tags.
            # Tags on an update commit are aggregated after a | ; tags on other
            # commits in between are shown one commit per line, prefixed with a
            # dash. Each range is handled by a single git log piped to one awk
            # pass, which keeps this reasonably fast on large histories.
            commit_list=$(git -C "$toplevel" log $list_sel --format="%H" -- "$sm_path" 2>/dev/null)

            body=$(
                idx=0
                printf "%s\n" "$commit_list" | while read -r cur; do
                    [ -z "$cur" ] && continue
                    idx=$((idx + 1))
                    if [ "$show_n" != "-1" ] && [ "$idx" -gt "$show_n" ]; then
                        break
                    fi

                    # Previous (older) update commit bounds the in-between range.
                    prev=$(printf "%s\n" "$commit_list" | sed -n "$((idx + 1))p")
                    if [ -n "$prev" ]; then
                        maxc=""
                        range="$prev..$cur"
                    elif [ -n "$final_lower" ]; then
                        maxc=""
                        range="$final_lower..$cur"
                    else
                        maxc="-1"
                        range="$cur"
                    fi

                    git -C "$toplevel" log $maxc $range --decorate=short --format="%h%x1f%s%x1f%D" 2>/dev/null |
                        awk -v REV="$ST_REVERSE" -v MODE="$ST_PORCELAIN" -v P="$displaypath" \
                            -v CSHA="$C_SHA" -v CTAG="$C_TAG" -v CDASH="$C_DASH" -v CRST="$C_RST" "$ST_AWK"
                done
            )
        fi

        body_err=$(git -C "$toplevel" log -1 --oneline -- "$sm_path" 2>&1 1>/dev/null)
        empty_msg="(no parent commits found)"
    else
        # Tags at the current commit (stdout) and any tag warnings (stderr).
        if [ -n "$ST_PORCELAIN" ]; then
            body=$(git tag --points-at HEAD 2>/dev/null | sort ${ST_REVERSE:+-r} |
                while read -r t; do
                    [ -n "$t" ] && printf "tag\t%s\t%s\n" "$displaypath" "$t"
                done)
        else
            body=$(git tag --points-at HEAD 2>/dev/null | sort ${ST_REVERSE:+-r} |
                while read -r t; do
                    [ -n "$t" ] && printf "%s%s%s\n" "$C_TAG" "$t" "$C_RST"
                done)
        fi
        body_err=$(git tag --points-at HEAD 2>&1 1>/dev/null)
        empty_msg="(no tags at current commit)"
    fi

    # Classify captured messages into warning/error status flags.
    all_msgs=$(printf "%s\n%s\n" "$fetch_err" "$body_err")
    warn=0
    err=0
    if printf "%s" "$all_msgs" | grep -qi "warning"; then
        warn=1
    fi
    if [ "$fetch_rc" -ne 0 ] || printf "%s" "$all_msgs" | grep -qi "error"; then
        err=1
    fi

    # Human-facing status suffix and machine-facing status field.
    status=""
    [ "$warn" = "1" ] && status="$status ${C_WARN}(Warning)${C_RST}"
    [ "$err" = "1" ] && status="$status ${C_ERR}(Error)${C_RST}"
    status_p=""
    [ "$warn" = "1" ] && status_p="warning"
    [ "$err" = "1" ] && status_p="${status_p:+$status_p }error"

    # In verbose mode, print the raw git warnings/errors to stderr.
    if [ -n "$ST_VERBOSE" ]; then
        [ -n "$fetch_err" ] && printf "%s\n" "$fetch_err" >&2
        [ -n "$body_err" ] && printf "%s\n" "$body_err" >&2
    fi

    if [ -n "$ST_PORCELAIN" ]; then
        printf "sub\t%s\t%s\t%s\n" "$displaypath" "$sha1" "$status_p"
        [ -n "$body" ] && printf "%s\n" "$body"
    else
        echo "${C_ARROW}===>${C_RST} ${C_PATH}${displaypath}${C_RST} (${C_SHA}${sha1}${C_RST})${status}"
        if [ -n "$body" ]; then
            echo "$body" | sed "s/^/  /"
        else
            echo "  $empty_msg"
        fi
    fi
'

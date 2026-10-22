#!/bin/bash

# ==============================================================================
# Filename:         ezwifiap.sh
# Description:      Quickly spin up a custom wifi ap that supports 2.4/5g, ipv4/ipv6,
#                   dhcp (ipv4, slaac, dhcpv6, ra only), dns, and traffic forwarding
#                   out another interface with real internet that may be ipv4 or
#                   ipv6 only.
# Author:           Adam A https://github.com/atariq11700
# Date Created:     2026-8-6
# License:          AGPL-3.0
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

dhcp4_range="50,100,1h"
dhcp6_range="100,1ff,1h"
ipv6_mode="both"
ipv6_prefix="fd00:1234:5678:1"
iface_addr="192.168.77.1"
uplink=""
enable_ipv4=false
enable_ipv6=false

# Get args
usage() {
    cat <<'EOF'
Usage: ezwifi_ap.sh <interface> <ssid> <password> (-4 and/or -6) [options]

  At least one of -4 / -6 must be given (both are off by default).

  -4                       enable IPv4 (DHCP)
  -6                       enable IPv6 (SLAAC + DHCPv6)
  -a <addr>                IPv4 interface address              (default 192.168.77.1)
  -p <prefix>              IPv6 /64 prefix                     (default fd00:1234:5678:1 for
                           local-only; 2001:db8:1:1 for NAT64 mode, see note below)
  -5 <ssid>                also start a 5GHz AP with this SSID
  -d <low>,<high>,<lease>  IPv4 DHCP pool (host octets) + lease (default 50,100,1h)
  -D <low>,<high>,<lease>  IPv6 DHCP pool (hex suffixes) + lease (default 100,1ff,1h)
  -m <slaac|dhcpv6|both|ra-stateless>  IPv6 address mode      (default both)
                           ra-stateless = SLAAC addr + DHCPv6 for DNS info only;
                             use this when Samsung devices fail to get an IPv6
                             address while other devices succeed (Samsung has a
                             DHCPv6 bug triggered by the M=1 flag in 'both' mode)
  -i <uplink>              NAT clients out this interface for real internet:
                           IPv4 masquerade, IPv6 via NAT64+DNS64. Omit for
                           local-only (no internet).

  NOTE (-6 with -i): Android (incl. Samsung) requires a Global Unicast Address
  (GUA, 2000::/3) for IPv6 provisioning. AOSP IpClient.java: "isIpv6Provisioned
  only returns true when it has a GUA". With a ULA prefix (fd00::/8) Android
  times out (~18 s) and disconnects even with a valid RA + DHCP option 108.
  This script auto-switches the prefix to 2001:db8:1:1 when -i is used and the
  prefix is still ULA; NAT64 provides real internet regardless of prefix routing.
EOF
    exit 1
}

if [[ $# -lt 3 ]]; then
    usage
fi

interface="$1"
ssid="$2"
password="$3"
shift 3

while getopts "a:46p:5:d:D:m:i:" opt; do
    case $opt in
        a) iface_addr="$OPTARG" ;;
        4) enable_ipv4=true ;;
        6) enable_ipv6=true ;;
        p) ipv6_prefix="$OPTARG"; ipv6_prefix_explicit=true ;;
        5) ssid_5g="$OPTARG" ;;
        d) dhcp4_range="$OPTARG" ;;
        D) dhcp6_range="$OPTARG" ;;
        m) ipv6_mode="$OPTARG" ;;
        i) uplink="$OPTARG" ;;
        *) usage ;;
    esac
done

if [[ $enable_ipv4 != true && $enable_ipv6 != true ]]; then
    echo "Error: enable at least one of -4 (IPv4) or -6 (IPv6)"
    usage
fi

# Android's LinkProperties.isIpv6Provisioned() only returns true for Global Unicast
# Addresses (GUA, 2000::/3); ULA (fc00::/7) is explicitly excluded via
# ConnectivityUtils.isIPv6ULA() — confirmed in AOSP IpClient.java.
# With only a ULA prefix the provisioning timeout fires after ~18 s and the device
# disconnects.  Auto-switch to a GUA when NAT64 is active and the user has not
# explicitly set a prefix with -p.  The GUA need not be globally routed because
# NAT64/TAYGA handles all IPv4 forwarding.
if [[ -n $uplink && $enable_ipv6 == true && ${ipv6_prefix_explicit:-false} == false ]]; then
    case $ipv6_prefix in
        fc*|fd*)
            echo "Note: NAT64 mode: auto-switching ULA prefix '$ipv6_prefix' to"
            echo "      '2001:db8:1:1'."
            echo "      Use -p to choose a different GUA prefix."
            ipv6_prefix="2001:db8:1:1"
            ;;
    esac
fi

# Split the "<low>,<high>,<lease>" DHCP specs into their parts.
IFS=',' read -r dhcp4_l dhcp4_h dhcp4_lease <<< "$dhcp4_range"
IFS=',' read -r dhcp6_l dhcp6_h dhcp6_lease <<< "$dhcp6_range"

# Build the IPv6 dhcp-range line from the requested mode. dnsmasq semantics:
#   both   - stateful DHCPv6 pool + SLAAC (RA M and A flags set)
#   dhcpv6 - stateful DHCPv6 pool only    (RA M flag; no A, so no SLAAC)
#   slaac  - ra-only: SLAAC only, no DHCPv6 server (RA A flag; no pool)
case $ipv6_mode in
    both)
        ip6_dhcp_range="dhcp-range=${ipv6_prefix}::${dhcp6_l},${ipv6_prefix}::${dhcp6_h},slaac,64,${dhcp6_lease}"
        ip6_desc="DHCPv6 ${ipv6_prefix}::${dhcp6_l}-::${dhcp6_h} + SLAAC, lease $dhcp6_lease"
        ;;
    dhcpv6)
        ip6_dhcp_range="dhcp-range=${ipv6_prefix}::${dhcp6_l},${ipv6_prefix}::${dhcp6_h},64,${dhcp6_lease}"
        ip6_desc="DHCPv6 ${ipv6_prefix}::${dhcp6_l}-::${dhcp6_h} only, lease $dhcp6_lease"
        ;;
    slaac)
        ip6_dhcp_range="dhcp-range=${ipv6_prefix}::,ra-only,64,${dhcp6_lease}"
        ip6_desc="SLAAC only, RA lifetime $dhcp6_lease"
        ;;
    ra-stateless)
        ip6_dhcp_range="dhcp-range=${ipv6_prefix}::,ra-stateless,64,${dhcp6_lease}"
        ip6_desc="RA-stateless (SLAAC addr + DHCPv6 info-only), lease $dhcp6_lease"
        ;;
    *)
        echo "Error: -m must be one of: slaac, dhcpv6, both, ra-stateless"
        usage
        ;;
esac

# Dependency and interface checks
missing=()
command -v hostapd &>/dev/null || missing+=("hostapd")
command -v dnsmasq &>/dev/null || missing+=("dnsmasq")
# NAT64 + DNS64 tooling is only needed when serving IPv6 internet via an uplink.
if [[ -n $uplink && $enable_ipv6 == true ]]; then
    command -v tayga &>/dev/null || missing+=("tayga")
    command -v unbound &>/dev/null || missing+=("unbound")
fi
if [[ ${#missing[@]} -gt 0 ]]; then
    echo "Error: missing required tools: ${missing[*]}"
    echo "  Install with: sudo apt install ${missing[*]}"
    echo "  or:           sudo pacman -S ${missing[*]}"
    echo "  or:           sudo dnf install ${missing[*]}"
    exit 1
fi

if ! ip link show "$interface" &>/dev/null; then
    echo "Error: interface '$interface' does not exist"
    echo "  Available interfaces: $(ip -o link show | awk -F': ' '{print $2}' | tr '
' ' ')"
    exit 1
fi

if [[ -n $uplink ]] && ! ip link show "$uplink" &>/dev/null; then
    echo "Error: uplink interface '$uplink' does not exist"
    exit 1
fi

# The transient DNS64 resolver this script starts (unbound on :5354) can't
# coexist with an already-running unbound: they share /run/unbound.pid, and a
# system unbound may also hold :53 on the AP address. Fail early with guidance
# rather than leaving client DNS silently broken.
if [[ -n $uplink && $enable_ipv6 == true ]] && pgrep -x unbound &>/dev/null; then
    echo "Error: an unbound instance is already running; it would conflict with the"
    echo "       transient DNS64 resolver this script needs to start."
    echo "  Stop it and keep it off at boot (it is not needed as a service):"
    echo "    sudo systemctl disable --now unbound.service unbound-resolvconf.service"
    exit 1
fi

# Setup hostapd conf
sed "s/@interface@/$interface/" "$SCRIPT_DIR/confs/ezhostapd.conf" |
    sed "s/@ssid@/$ssid/" > /tmp/ezwifi_hostapd.conf
if [[ -n $password ]]; then
    printf 'wpa=2\nwpa_passphrase=%s\nwpa_key_mgmt=WPA-PSK\nwpa_pairwise=CCMP\nrsn_pairwise=CCMP\n' "$password" >> /tmp/ezwifi_hostapd.conf
fi

if [[ -n $ssid_5g ]]; then
    phy=$(iw dev "$interface" info | grep wiphy | awk '{print "phy"$2}')
    dual_band=false
    if iw phy "$phy" info | grep -q "valid interface combinations"; then
        if iw phy "$phy" info | grep -A 5 "valid interface combinations" | grep -q "AP.*AP\|#channels <= [2-9]"; then
            dual_band=true
        fi
    fi

    if [[ $dual_band == true ]]; then
        iface_5g="${interface}_5g"
        sudo iw dev "$iface_5g" del 2>/dev/null
        sudo iw dev "$interface" interface add "$iface_5g" type __ap
    else
        echo "Warning: hardware does not support simultaneous dual-band AP. Starting 5GHz only."
        skip_2g=true
        iface_5g="$interface"
    fi

    ch_5g=$(iw phy "$phy" info | awk '/Band 2:/,0' | grep "MHz" | grep -v "no IR\|radar" | grep -oP '\[\K[0-9]+(?=\])' | head -1)
    if [[ -z $ch_5g ]]; then
        echo "Error: no usable 5GHz channels found on $interface"
        exit 1
    fi

    sed "s/@interface@/$iface_5g/" "$SCRIPT_DIR/confs/ezhostapd.conf" |
        sed "s/@ssid@/$ssid_5g/" |
        sed "s/hw_mode=g/hw_mode=a/" |
        sed "s/channel=7/channel=$ch_5g/" > /tmp/ezwifi_hostapd_5g.conf
    if [[ -n $password ]]; then
        printf 'wpa=2\nwpa_passphrase=%s\nwpa_key_mgmt=WPA-PSK\nwpa_pairwise=CCMP\nrsn_pairwise=CCMP\n' "$password" >> /tmp/ezwifi_hostapd_5g.conf
    fi
fi

# Calculate addr stuff for dnsmasq.
# An IPv4 address is always assigned regardless of whether -4 was given:
# in IPv6-only mode we still need one to serve the RFC 8925 DHCPv4 stub
# (option 108 / IPv6-Only Preferred) that tells Android and other devices
# to stop waiting for a real IPv4 lease and use IPv6 instead. Without this
# response, devices show "Can't get IP address" and never send any IPv6 traffic.
current_addr=$(ip -4 addr show "$interface" 2>/dev/null | grep -oP 'inet \K[\d.]+')
if [[ -n $current_addr && $current_addr != "$iface_addr" ]]; then
    sudo ip addr del "$current_addr/24" dev "$interface"
fi
sudo ip addr add "$iface_addr/24" dev "$interface" 2>/dev/null
subnet_prefix="${iface_addr%.*}"
dhcp_range_l="${subnet_prefix}.${dhcp4_l}"
dhcp_range_h="${subnet_prefix}.${dhcp4_h}"

# Assign an IPv6 ULA to the interface. This is served entirely locally, so
# clients get working IPv6 (SLAAC + DHCPv6) even if the host PC has no IPv6
# internet access. Per-interface forwarding is enabled so we are a valid
# router on this link without disabling RA acceptance on other interfaces.
if [[ $enable_ipv6 == true ]]; then
    iface_addr6="${ipv6_prefix}::1"
    sudo ip -6 addr del "${iface_addr6}/64" dev "$interface" 2>/dev/null
    # nodad: skip Duplicate Address Detection so the address is immediately
    # usable (never tentative). This avoids a race where dnsmasq reads the
    # interface before DAD completes and advertises no prefix to clients.
    sudo ip -6 addr add "${iface_addr6}/64" dev "$interface" nodad
    sudo sysctl -qw "net.ipv6.conf.$interface.forwarding=1" >/dev/null 2>&1

    # Ensure the interface has a link-local (fe80::) address. Router
    # Advertisements and DHCPv6 replies MUST be sourced from link-local, but
    # many interfaces (esp. USB Wi-Fi adapters) come up with addr_gen_mode=none,
    # so the kernel never auto-generates one. Without it dnsmasq's RA/DHCPv6
    # packets can't egress and clients only ever get a fe80:: address of their
    # own. Add a deterministic link-local so the AP can advertise the prefix.
    iface_addr6_ll="fe80::1"
    if ! ip -6 addr show dev "$interface" scope link | grep -q "inet6 fe80:"; then
        sudo ip -6 addr add "${iface_addr6_ll}/64" dev "$interface" nodad
        added_ll=true
    fi
fi

# Setup dnsmasq conf. Strip the IPv4 and/or IPv6 blocks from the template
# depending on which protocols are enabled (marker lines delimit each block).
dnsmasq_conf=$(cat "$SCRIPT_DIR/confs/ezdnsmasq.conf")
if [[ $enable_ipv4 == true ]]; then
    # Real IPv4 DHCP; drop the IPv6-only-preferred stub.
    dnsmasq_conf=$(sed '/#@IPV4-BEGIN@/d;/#@IPV4-END@/d' <<< "$dnsmasq_conf")
else
    # No real IPv4; drop the normal IPv4 block.
    dnsmasq_conf=$(sed '/#@IPV4-BEGIN@/,/#@IPV4-END@/d' <<< "$dnsmasq_conf")
fi
if [[ $enable_ipv6 == true ]]; then
    dnsmasq_conf=$(sed '/#@IPV6-BEGIN@/d;/#@IPV6-END@/d' <<< "$dnsmasq_conf")
else
    dnsmasq_conf=$(sed '/#@IPV6-BEGIN@/,/#@IPV6-END@/d' <<< "$dnsmasq_conf")
fi

sed "s/@interface@/$interface/" <<< "$dnsmasq_conf" |
    sed "s/@lowerip@/$dhcp_range_l/" |
    sed "s/@upperip@/$dhcp_range_h/" |
    sed "s/@leasetime@/$dhcp4_lease/" |
    sed "s|@ip6dhcprange@|$ip6_dhcp_range|" |
    sed "s/@interfaceip6@/$iface_addr6/" |
    sed "s/@interfaceip@/$iface_addr/" > /tmp/ezwifi_dnsmasq.conf

# --- Real internet (NAT), only when an uplink is given with -i ---
# Without -i the AP stays local-only (no forwarding, no NAT). With -i:
#   IPv4 clients are masqueraded out the uplink.
#   IPv6 clients reach the (IPv4) internet via NAT64 (tayga, prefix 64:ff9b::/96)
#   plus DNS64 (unbound synthesizing AAAA), so it works even on IPv4-only hosts.
nat64_prefix="64:ff9b::/96"
# All NAT/forwarding rules live in a dedicated "EZWIFI" chain (one per table)
# that the built-in chains jump to, so teardown is just: unlink the jump, then
# flush and delete the chain. Idempotent, so a fresh run also clears stale
# chains left by a previous crash.
ez_chain="EZWIFI"

nat_teardown() {
    sudo iptables -t nat -D POSTROUTING -j "$ez_chain" 2>/dev/null
    sudo iptables        -D FORWARD     -j "$ez_chain" 2>/dev/null
    sudo ip6tables       -D FORWARD     -j "$ez_chain" 2>/dev/null
    sudo iptables -t nat -F "$ez_chain" 2>/dev/null; sudo iptables -t nat -X "$ez_chain" 2>/dev/null
    sudo iptables        -F "$ez_chain" 2>/dev/null; sudo iptables        -X "$ez_chain" 2>/dev/null
    sudo ip6tables       -F "$ez_chain" 2>/dev/null; sudo ip6tables       -X "$ez_chain" 2>/dev/null
}

nat_setup() {
    nat_teardown

    # IPv4: one MASQUERADE on the uplink covers everything leaving it (the client
    # subnet and, when active, tayga's NAT64 pool). Allow forwarding for new
    # client flows plus all established/related return traffic.
    sudo iptables -t nat -N "$ez_chain"
    sudo iptables -t nat -I POSTROUTING -j "$ez_chain"
    sudo iptables -t nat -A "$ez_chain" -o "$uplink" -j MASQUERADE

    sudo iptables -N "$ez_chain"
    sudo iptables -I FORWARD -j "$ez_chain"
    sudo iptables -A "$ez_chain" -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
    sudo iptables -A "$ez_chain" -i "$interface" -j ACCEPT
    [[ $nat64_active == true ]] && sudo iptables -A "$ez_chain" -i nat64 -j ACCEPT

    # IPv6: only needed so clients can reach the NAT64 translator (tayga).
    if [[ $nat64_active == true ]]; then
        sudo ip6tables -N "$ez_chain"
        sudo ip6tables -I FORWARD -j "$ez_chain"
        sudo ip6tables -A "$ez_chain" -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
        sudo ip6tables -A "$ez_chain" -i "$interface" -j ACCEPT
    fi
}

# Policy routing: send everything that arrived on an AP-side interface out the
# chosen uplink, even when it is not the system default route. Matching on the
# inbound interface (iif) rather than the source address is the key: the
# router's own packets (e.g. dnsmasq's replies to clients) are locally
# generated, so they never match iif and are delivered normally via the main
# table - only forwarded client traffic is pinned to the uplink. Traffic to the
# router itself and between clients is handled by the kernel's local table /
# L2, so no exceptions are needed here.
ez_rt_table=5064
ez_rt_prio=5064

route_teardown() {
    while sudo ip -4 rule del priority "$ez_rt_prio" 2>/dev/null; do :; done
    sudo ip -4 route flush table "$ez_rt_table" 2>/dev/null
}

route_setup() {
    route_teardown
    local gw
    gw=$(ip -4 route show default dev "$uplink" 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="via"){print $(i+1); exit}}')
    if [[ -n $gw ]]; then
        sudo ip -4 route replace default via "$gw" dev "$uplink" table "$ez_rt_table"
    else
        sudo ip -4 route replace default dev "$uplink" table "$ez_rt_table"
    fi
    sudo ip -4 rule add iif "$interface" lookup "$ez_rt_table" priority "$ez_rt_prio"
    [[ $nat64_active == true ]] && sudo ip -4 rule add iif nat64 lookup "$ez_rt_table" priority "$ez_rt_prio"
}

if [[ -n $uplink ]]; then
    if [[ $enable_ipv4 == true ]]; then
        sudo sysctl -qw net.ipv4.ip_forward=1 >/dev/null
    fi
    if [[ $enable_ipv6 == true ]]; then
        # Stand up NAT64 so IPv6 clients can reach the IPv4 internet. Tayga's
        # egress is IPv4, so IPv4 forwarding is required here too.
        sudo sysctl -qw net.ipv4.ip_forward=1 >/dev/null
        sudo sysctl -qw net.ipv6.conf.all.forwarding=1 >/dev/null

        # Derive tayga's addresses from the user's flags so no hardcoded default
        # can clash with them. The IPv4 pool uses CGN space (RFC 6598), shifted
        # once if the client's -a subnet happens to land on it; the IPv6
        # ICMPv6-source address sits in a sibling /64 of the client prefix (-p),
        # so it can never overlap the client /64 or its DHCPv6 pool (-D).
        tayga_net="100.64.0"
        [[ $subnet_prefix == "$tayga_net" ]] && tayga_net="100.64.1"
        tayga_pool="${tayga_net}.0/24"
        tayga_ipv4="${tayga_net}.1"
        tayga_ipv6="${ipv6_prefix%:*}:64::1"
        sed "s/@tayga_ipv4@/$tayga_ipv4/" "$SCRIPT_DIR/confs/eztayga.conf" |
            sed "s/@tayga_ipv6@/$tayga_ipv6/" |
            sed "s|@tayga_pool@|$tayga_pool|" > /tmp/ezwifi_tayga.conf

        mkdir -p /tmp/ezwifi_tayga
        sudo tayga --mktun -c /tmp/ezwifi_tayga.conf >/dev/null 2>&1
        sudo ip link set nat64 up
        sudo ip addr add "$tayga_ipv4" dev nat64 2>/dev/null
        sudo ip route add "$tayga_pool" dev nat64 2>/dev/null
        sudo ip -6 route add "$nat64_prefix" dev nat64 2>/dev/null
        nat64_active=true
    fi
    nat_setup
    route_setup
fi

# dnsmasq upstream: point at the local DNS64 resolver when NAT64 is active
# (single upstream so every AAAA is synthesized consistently), else the public
# resolvers directly.
if [[ $nat64_active == true ]]; then
    echo "server=127.0.0.1#5354" >> /tmp/ezwifi_dnsmasq.conf
else
    printf 'server=8.8.8.8\nserver=8.8.4.4\n' >> /tmp/ezwifi_dnsmasq.conf
fi

# RA router lifetime: advertise ourselves as a default router only when we can
# actually forward to the internet. In local-only mode advertise lifetime 0 so
# clients don't blackhole their global IPv6 traffic through us.
if [[ $enable_ipv6 == true ]]; then
    if [[ -n $uplink ]]; then
        echo "ra-param=$interface,600,1800" >> /tmp/ezwifi_dnsmasq.conf
    else
        echo "ra-param=$interface,600,0" >> /tmp/ezwifi_dnsmasq.conf
    fi
fi



# Run hostapd and dnsmasq

cleanup() {
    echo "Stopping hostapd and dnsmasq..."
    sudo kill "$hostapd_pid" 2>/dev/null
    [[ -n $hostapd_5g_pid ]] && sudo kill "$hostapd_5g_pid" 2>/dev/null
    sudo kill "$dnsmasq_pid" 2>/dev/null
    [[ -n $tayga_pid ]] && sudo kill "$tayga_pid" 2>/dev/null
    [[ -n $unbound_pid ]] && sudo kill "$unbound_pid" 2>/dev/null
    [[ $nat64_active == true ]] && sudo rm -f /etc/unbound/ezwifi_unbound.conf 2>/dev/null
    [[ -n $uplink ]] && nat_teardown
    [[ -n $uplink ]] && route_teardown
    [[ $nat64_active == true ]] && sudo ip link del nat64 2>/dev/null
    [[ $enable_ipv4 == true || $enable_ipv6 == true ]] && sudo ip addr del "$iface_addr/24" dev "$interface" 2>/dev/null
    [[ $enable_ipv6 == true ]] && sudo ip -6 addr del "$iface_addr6/64" dev "$interface" 2>/dev/null
    [[ $added_ll == true ]] && sudo ip -6 addr del "$iface_addr6_ll/64" dev "$interface" 2>/dev/null
    [[ -n $iface_5g && $iface_5g != "$interface" ]] && sudo iw dev "$iface_5g" del 2>/dev/null
    wait
}

trap cleanup EXIT
trap 'exit 1' INT TERM

if [[ $skip_2g != true ]]; then
    sudo hostapd /tmp/ezwifi_hostapd.conf &
    hostapd_pid=$!
fi

if [[ -n $ssid_5g ]]; then
    sudo hostapd /tmp/ezwifi_hostapd_5g.conf &
    hostapd_5g_pid=$!
fi

if [[ $nat64_active == true ]]; then
    sudo tayga -d -c /tmp/ezwifi_tayga.conf &
    tayga_pid=$!
    # unbound is AppArmor-confined and may only read configs under /etc/unbound,
    # so stage ours there instead of running it from the repo path.
    sudo cp "$SCRIPT_DIR/confs/ezunbound.conf" /etc/unbound/ezwifi_unbound.conf
    sudo unbound -d -c /etc/unbound/ezwifi_unbound.conf &
    unbound_pid=$!
fi

sudo dnsmasq -C /tmp/ezwifi_dnsmasq.conf -d &
dnsmasq_pid=$!

sleep 5

[[ $skip_2g != true ]] && echo "2.4GHz AP running on $interface (SSID: $ssid)"
[[ -n $ssid_5g ]] && echo "5GHz AP running on $iface_5g (SSID: $ssid_5g, channel: $ch_5g)"
if [[ $enable_ipv4 == true ]]; then
    echo "IPv4 on $interface: $iface_addr/24 (DHCP $dhcp_range_l-$dhcp_range_h, lease $dhcp4_lease)${uplink:+ [NAT -> $uplink]}"
else
    echo "IPv4 on $interface: $iface_addr/24 (RFC 8925 stub: option-108 only, no routing)"
fi
if [[ $enable_ipv6 == true ]]; then
    if [[ $nat64_active == true ]]; then
        echo "IPv6 (ULA) on $interface: $iface_addr6/64 ($ip6_desc) [NAT64+DNS64 -> $uplink]"
    else
        echo "IPv6 (ULA) on $interface: $iface_addr6/64 ($ip6_desc, local-only)"
    fi
fi
echo "Press Ctrl+C to stop"
echo ""
echo "Commands: txpower <auto|fixed|limit> [mBm]  |  status  |  clients  |  quit"

while true; do
    read -r -p "> " cmd args extra || break
    case $cmd in
        txpower)
            read -r tx_mode tx_power tx_iface <<< "$args $extra"
            tx_iface=${tx_iface:-$interface}
            case $tx_mode in
                auto)
                    sudo iw dev "$tx_iface" set txpower auto
                    ;;
                fixed|limit)
                    if [[ -z $tx_power ]]; then
                        echo "Usage: txpower fixed|limit <power_mBm> [interface]"
                    else
                        sudo iw dev "$tx_iface" set txpower "$tx_mode" "$tx_power"
                    fi
                    ;;
                *)
                    echo "Usage: txpower <auto|fixed|limit> [power_mBm] [interface]"
                    ;;
            esac
            ;;
        status)
            iw dev "$interface" info
            [[ -n $iface_5g && $iface_5g != "$interface" ]] && iw dev "$iface_5g" info
            ;;
        clients)
            iw dev "$interface" station dump
            [[ -n $iface_5g && $iface_5g != "$interface" ]] && iw dev "$iface_5g" station dump
            ;;
        quit|exit)
            exit 0
            ;;
        "")
            ;;
        *)
            echo "Unknown command: $cmd"
            echo "Commands: txpower <auto|fixed|limit> [mBm]  |  status  |  clients  |  quit"
            ;;
    esac
done

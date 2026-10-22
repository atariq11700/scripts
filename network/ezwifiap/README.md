# ezwifiap

A throwaway wifi access point you can bring up in one command, built for testing how devices behave on different network setups.

## Purpose

Standing up an access point with DHCP, DNS, and internet sharing normally means configuring several services by hand. This tool wires them together and tears them down when you are done, which makes it easy to test clients against IPv4-only, IPv6-only, and dual-stack networks.

## What it supports

- 2.4 GHz, with an optional second 5 GHz network under its own name
- IPv4 only, IPv6 only, or both
- IPv4 DHCP and IPv6 addressing through SLAAC, DHCPv6, both, or router advertisements with DHCPv6 for DNS only
- Local DNS for clients
- Local-only networks with no internet, or sharing internet from another interface
- IPv4 sharing through NAT
- IPv6-only clients reaching the IPv4 internet through NAT64 and DNS64
- Workarounds for Android and Samsung IPv6 provisioning quirks

## What it does not do

- Act as a permanent router or persist configuration between runs
- Provide internet access in local-only mode

## Requirements

- Linux
- A wifi adapter that supports access point mode (and 5 GHz, for the second network)
- Root privileges
- `hostapd` and `dnsmasq`
- `tayga` and `unbound`, for NAT64/DNS64

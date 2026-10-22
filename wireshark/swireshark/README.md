# swireshark

Live packet capture from a remote machine, viewed in a local Wireshark.

## Purpose

Inspect traffic on a remote host with the full Wireshark interface, without installing Wireshark there or copying capture files back and forth.

## What it does

- Streams a capture from the remote host over ssh into a local Wireshark window
- Captures inside a chosen Linux network namespace on the remote host
- Starts from an existing Wireshark profile
- Leaves your Wireshark preferences unchanged; settings changed during the session are not saved

## Requirements

- Bash
- Wireshark on the local machine
- ssh access to the remote host
- `tcpdump` on the remote host, with permission to capture

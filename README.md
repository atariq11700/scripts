<div align="center">

# scratch

**A workbench of personal utilities, dotfiles, and editor tweaks.**

![License: AGPL-3.0](https://img.shields.io/badge/license-AGPL--3.0-blue?style=for-the-badge)
![Bash](https://img.shields.io/badge/Bash-4EAA25?style=for-the-badge&logo=gnubash&logoColor=white)
![Python](https://img.shields.io/badge/Python-3776AB?style=for-the-badge&logo=python&logoColor=white)
![PowerShell](https://img.shields.io/badge/PowerShell-5391FE?style=for-the-badge&logo=powershell&logoColor=white)
![Windows](https://img.shields.io/badge/Windows-0078D4?style=for-the-badge&logo=windows&logoColor=white)
![Linux](https://img.shields.io/badge/Linux-FCC624?style=for-the-badge&logo=linux&logoColor=black)

[About](#about) &nbsp;|&nbsp; [Directories](#directories) &nbsp;|&nbsp; [Projects](#projects) &nbsp;|&nbsp; [License](#license)

</div>

---

## About

This repository collects small, self-contained tools that solve everyday problems: inspecting git submodules, standing up a wifi access point on demand, driving a bench power supply, capturing remote traffic, and keeping shell and editor setups consistent across machines.

Each project lives in its own directory with its own README describing what it is for, what it supports, and what it needs. Usage details live in the tools themselves.

## Directories

Top-level directories group projects by the tool or domain they belong to.

| Directory | Contents |
| :--- | :--- |
| [`git`](git) | Git utilities and helpers |
| [`korad`](korad) | Tools for Korad programmable power supplies |
| [`network`](network) | Networking utilities, tools, and scripts |
| [`user`](user) | Per-user setup: shell profile, dotfiles, and general-purpose scripts |
| [`vscode`](vscode) | VS Code customizations and extension configuration |
| [`wireshark`](wireshark) | Wireshark and packet capture helpers |

## Projects

- **[submoduletags](git/submoduletags)**: Reports the tags and recent update history for every submodule in a git repository, recursively.
- **[korad](korad)**: Terminal interface for monitoring and controlling single-channel Korad power supplies.
- **[ezwifiap](network/ezwifiap)**: One-command wifi access point with dual-band, IPv4/IPv6, and NAT64/DNS64 support.
- **[dotfiles](user/profile/dotfiles)**: Shared bash profile and git shell helpers that work across machines.
- **[scripts](user/scripts)**: General-purpose standalone scripts, including a CRC-32 checksum tool.
- **[windows_cli_admin_launcher](user)**: Elevated launcher menu for common Windows administration tools.
- **[custom-css-js](vscode/custom-css-js)**: Custom styling for the VS Code interface.
- **[macro-commander git macros](vscode/macro-commander/git)**: Extra GitLens compare actions for VS Code.
- **[swireshark](wireshark/swireshark)**: Live remote packet capture streamed into a local Wireshark.

## License

Released under the [AGPL-3.0](LICENSE).

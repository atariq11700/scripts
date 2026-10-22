# user

Per-user tooling. See also [dotfiles](profile/dotfiles) and [scripts](scripts).

## windows_cli_admin_launcher

An elevated launcher menu for common Windows administration tools.

### Purpose

Get to Device Manager, Disk Management, Task Manager, and similar tools from one menu in an administrator session, instead of hunting through Windows menus.

### What it does

- Re-launches itself with administrator rights when needed
- Presents a menu of common admin tools, including Sysinternals tools when installed
- Lets you extend the menu with your own entries
- Optionally closes itself after launching a tool
- Can create a shortcut that always runs as administrator

### Requirements

- Windows
- PowerShell 5.1 or later
- An account that can elevate

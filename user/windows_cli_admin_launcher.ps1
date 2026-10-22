# ==============================================================================
# Filename:         windows_cli_admin_launcher.ps1
# Description:      Self-elevating menu for quickly launching common Windows admin
#                   tools, with an option to create a run-as-administrator shortcut.
# Author:           Adam A https://github.com/atariq11700
# Date Created:     2026-10-21
# License:          AGPL-3.0
# ==============================================================================

#Requires -Version 5.1
param([switch]$CreateShortcut)

if ($CreateShortcut) {
    $lnk = Join-Path $PSScriptRoot 'QuickAdmin.lnk'
    $wsh = New-Object -ComObject WScript.Shell
    $sc  = $wsh.CreateShortcut($lnk)
    $sc.TargetPath  = 'powershell.exe'
    $sc.Arguments   = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    $sc.WindowStyle = 1
    $sc.Save()
    # Set RunAsAdministrator flag (byte 21, bit 5)
    $b = [IO.File]::ReadAllBytes($lnk); $b[21] = $b[21] -bor 0x20; [IO.File]::WriteAllBytes($lnk, $b)
    Write-Host "Shortcut created: $lnk"
    exit
}

# Self-elevate if not already running as Administrator
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Start-Process powershell -Verb RunAs `
        -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    exit
}

# =============================================================================
# TASK LIST — add entries here to extend the menu
# Each entry needs a Name (display label) and Command (executable + args)
# =============================================================================
$tasks = @(
    [PSCustomObject]@{ Name = 'Device Manager';             Command = 'devmgmt.msc' }
    [PSCustomObject]@{ Name = 'Disk Management';            Command = 'diskmgmt.msc' }
    [PSCustomObject]@{ Name = 'Environment Variables';      Command = 'rundll32 sysdm.cpl,EditEnvironmentVariables' }
    [PSCustomObject]@{ Name = 'Control Panel';              Command = 'control' }
    [PSCustomObject]@{ Name = 'Network Adapter Settings';   Command = 'ncpa.cpl' }
    [PSCustomObject]@{ Name = 'Windows Terminal';           Command = 'wt' }
    [PSCustomObject]@{ Name = 'PowerShell';                 Command = 'powershell' }
    [PSCustomObject]@{ Name = 'Command Prompt';             Command = 'cmd' }
    [PSCustomObject]@{ Name = 'Task Manager';               Command = 'taskmgr' }
    [PSCustomObject]@{ Name = 'Process Explorer';           Command = "`"$env:ProgramFiles\Process Explorer\procexp.exe`"" }
    [PSCustomObject]@{ Name = 'Process Monitor';            Command = "`"$env:ProgramFiles\Process Monitor\Procmon.exe`"" }


)
# =============================================================================

$settingsDir  = Join-Path $env:APPDATA 'QuickAdminLauncher'
$settingsPath = Join-Path $settingsDir 'settings.json'

function Get-AutoCloseSetting {
    if (Test-Path $settingsPath) {
        try {
            return [bool](Get-Content $settingsPath -Raw | ConvertFrom-Json).AutoClose
        } catch { }
    }
    return $true
}

function Set-AutoCloseSetting ([bool]$value) {
    if (-not (Test-Path $settingsDir)) { New-Item -ItemType Directory -Path $settingsDir | Out-Null }
    [PSCustomObject]@{ AutoClose = $value } | ConvertTo-Json | Set-Content $settingsPath
}

function Start-SelectedTask ([PSCustomObject]$task) {
    # Commands may be a quoted path (handles spaces, e.g. "C:\Program Files\...\x.exe") or a bare exe + args
    if ($task.Command.StartsWith('"')) {
        $endQuote = $task.Command.IndexOf('"', 1)
        $exe      = $task.Command.Substring(1, $endQuote - 1)
        $argList  = $task.Command.Substring($endQuote + 1).Trim()
        if ($argList -eq '') { $argList = $null }
    } else {
        $parts   = $task.Command -split ' ', 2
        $exe     = $parts[0]
        $argList = if ($parts.Count -gt 1) { $parts[1] } else { $null }
    }
    try {
        if ($argList) {
            Start-Process -FilePath $exe -ArgumentList $argList -ErrorAction Stop
        } else {
            Start-Process -FilePath $exe -ErrorAction Stop
        }
        return [PSCustomObject]@{ Success = $true;  Message = ('Launched: {0}' -f $task.Name) }
    } catch {
        return [PSCustomObject]@{ Success = $false; Message = ("Failed to start '{0}': {1}" -f $task.Name, $_.Exception.Message) }
    }
}

function Draw-Menu ([int]$sel, [bool]$autoClose, [string]$statusMsg = '') {
    $nameW = ($tasks | ForEach-Object { $_.Name.Length } | Measure-Object -Maximum).Maximum
    $width = [Math]::Max(0, [Console]::WindowWidth - 1)

    for ($i = 0; $i -lt $tasks.Count; $i++) {
        $prefix = if ($i -eq $sel) { '*' } else { ' ' }
        $num    = '[{0}]' -f ($i + 1)
        $name   = $tasks[$i].Name.PadRight($nameW)
        $line   = ('{0} {1}  {2}  {3}' -f $prefix, $num, $name, $tasks[$i].Command).PadRight($width)
        if ($i -eq $sel) {
            Write-Host $line -ForegroundColor Black -BackgroundColor Cyan
        } else {
            Write-Host $line
        }
    }
    Write-Host ''.PadRight($width)
    $acState = if ($autoClose) { 'ON' } else { 'OFF' }
    Write-Host ('  [Up/Dn] navigate   [Enter] launch   number [1-{0}]   [a] auto-close: {1}   [Esc] exit' -f [Math]::Min($tasks.Count, 9), $acState).PadRight($width)

    # Wrap the status message across a fixed number of lines so long errors are never clipped
    $remaining = $statusMsg
    for ($i = 0; $i -lt $StatusLineCount; $i++) {
        if ($remaining.Length -gt $width) {
            $chunk     = $remaining.Substring(0, $width)
            $remaining = $remaining.Substring($width)
        } else {
            $chunk     = $remaining
            $remaining = ''
        }
        $line = $chunk.PadRight($width)
        if ($i -eq $StatusLineCount - 1) { Write-Host $line -NoNewline } else { Write-Host $line }
    }
}

# --- Main ---
Clear-Host
Write-Host '=== Admin Launcher ===' -ForegroundColor Cyan
Write-Host ''

$selected  = 0
$autoClose = Get-AutoCloseSetting
$StatusLineCount = 3
$menuTop   = [Console]::CursorTop

Draw-Menu -sel $selected -autoClose $autoClose

while ($true) {
    $key = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')

    switch ($key.VirtualKeyCode) {
        38 {  # Up arrow
            if ($selected -gt 0) { $selected-- }
            [Console]::SetCursorPosition(0, $menuTop)
            Draw-Menu -sel $selected -autoClose $autoClose
        }
        40 {  # Down arrow
            if ($selected -lt ($tasks.Count - 1)) { $selected++ }
            [Console]::SetCursorPosition(0, $menuTop)
            Draw-Menu -sel $selected -autoClose $autoClose
        }
        13 {  # Enter - launch; close only if auto-close is on and it succeeded
            $result = Start-SelectedTask -task $tasks[$selected]
            if ($result.Success -and $autoClose) {
                exit
            }
            [Console]::SetCursorPosition(0, $menuTop)
            Draw-Menu -sel $selected -autoClose $autoClose -statusMsg $result.Message
        }
        27 {  # Escape - exit without launching
            [Console]::SetCursorPosition(0, $menuTop + $tasks.Count + 2 + $StatusLineCount)
            Write-Host ''
            exit
        }
        default {
            $char = [string]$key.Character
            if ($char -match '^[1-9]$') {
                $idx = [int]$char - 1
                if ($idx -lt $tasks.Count) {
                    $selected = $idx
                    [Console]::SetCursorPosition(0, $menuTop)
                    Draw-Menu -sel $selected -autoClose $autoClose
                }
            } elseif ($char -match '^[aA]$') {
                $autoClose = -not $autoClose
                Set-AutoCloseSetting -value $autoClose
                [Console]::SetCursorPosition(0, $menuTop)
                Draw-Menu -sel $selected -autoClose $autoClose
            }
        }
    }
}

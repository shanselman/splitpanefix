# Fix-SplitPanePersistence

**One-click fix for Windows Terminal split panes and duplicate tabs to preserve your current working directory.**

When you split a pane or duplicate a tab in Windows Terminal, the new pane often opens in your home directory instead of staying where you were. This script fixes that permanently.

## The Problem

By default, Windows Terminal doesn't know what directory your shell is in. When you press `Alt+Shift+-` to split horizontally or `Ctrl+Shift+D` to duplicate a tab, the new shell starts fresh in `~` or `C:\Users\YourName`.

This is frustrating when you're deep in a project folder and want a second terminal right there.

## The Solution

This script configures three things to work together:

1. **Oh My Posh** emits [OSC 99 escape sequences](https://github.com/JanDeDobbeleer/oh-my-posh/discussions/1532) that tell Windows Terminal your current directory
2. **Windows Terminal** keybindings use `splitMode: duplicate` to inherit that directory
3. **Your PowerShell profile** is set up correctly to make it all work

## Quick Start

```powershell
# Preview what will change (no modifications)
.\Fix-SplitPanePersistence.ps1 -WhatIf

# Apply the fix
.\Fix-SplitPanePersistence.ps1

# Restart your terminal
```

## What It Does

### 1. PowerShell Profile (`$PROFILE`)
- Creates your profile if it doesn't exist
- Ensures Oh My Posh is initialized with `oh-my-posh init pwsh --config '<theme>' | Invoke-Expression`
- Comments out any custom `function prompt { }` blocks that would override Oh My Posh (with backup)
- Removes duplicate Oh My Posh init lines if present

### 2. Oh My Posh Theme
- Locates your active theme from the profile
- Adds `"pwd": "osc99"` to the theme's root JSON object
- If the theme is in the built-in themes folder, copies it to `%LOCALAPPDATA%\oh-my-posh\themes` first (so updates don't overwrite your changes)

### 3. Windows Terminal Settings
- Adds or updates keybindings in `settings.json`:

| Shortcut | Action |
|----------|--------|
| `Alt+Shift+-` | Split pane horizontally (same directory) |
| `Alt+Shift++` | Split pane vertically (same directory) |
| `Ctrl+Shift+D` | Duplicate tab (same directory) |

## Why This Should Be the Default

The current default behavior is surprising and unproductive:

- **User expectation**: "I want another terminal *here*"
- **Current behavior**: New terminal opens in home directory
- **Context switching cost**: User must `cd` back to their project every time

Most users discover this pain point and then spend time researching OSC escape codes, shell integrations, and Windows Terminal settings. This script encapsulates that research into a single command.

### Technical Background

Windows Terminal can preserve the working directory, but only if the shell *tells* it where you are. PowerShell doesn't do this by default. Oh My Posh can emit the necessary escape sequence (OSC 99) when configured with `"pwd": "osc99"` in the theme.

The `splitMode: duplicate` setting in Windows Terminal keybindings tells it to use shell integration features (like OSC 99) rather than spawning a fresh shell.

## Parameters

| Parameter | Description |
|-----------|-------------|
| `-WhatIf` | Dry run mode. Shows what would change without modifying anything. |
| `-Verbose` | Detailed logging of all operations. |
| `-ThemePath` | Custom directory for user-writable themes (default: `%LOCALAPPDATA%\oh-my-posh\themes`). |

## Safety Features

- **Backups**: Every modified file gets a timestamped backup (e.g., `settings.json.bak-20240115-143022`)
- **Idempotent**: Safe to run multiple times. Re-running when already configured makes no changes.
- **Graceful degradation**: If Oh My Posh isn't installed, the script still configures Windows Terminal keybindings.

## Rollback

To undo changes, restore from backups:

```powershell
# Find backups
Get-ChildItem $env:USERPROFILE -Filter "*.bak-*" -Recurse
Get-ChildItem "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal*" -Filter "*.bak-*" -Recurse

# Restore a backup (example)
Copy-Item "settings.json.bak-20240115-143022" "settings.json"
```

## Requirements

- Windows 11 (or Windows 10 with Windows Terminal)
- PowerShell 7+ (`pwsh`)
- Windows Terminal (Store or standalone)
- Oh My Posh v11+ (optional, but recommended)

## References

- [Microsoft Docs: New tab same directory](https://learn.microsoft.com/en-us/windows/terminal/tutorials/new-tab-same-directory#powershell-powershellexe-or-pwshexe) - Official tutorial on shell integration
- [Oh My Posh Discussion #1532](https://github.com/JanDeDobbeleer/oh-my-posh/discussions/1532) - Original discussion on OSC 99 support
- [Windows Terminal Shell Integration](https://learn.microsoft.com/en-us/windows/terminal/tutorials/shell-integration) - Deep dive on escape sequences

## License

MIT

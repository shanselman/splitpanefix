# Fix-SplitPanePersistence

**One-click fix for Windows Terminal split panes and duplicate tabs to preserve your current working directory.**

When you split a pane or duplicate a tab in Windows Terminal, the new pane often opens in your home directory instead of staying where you were. This script fixes that permanently.

## The Problem

By default, Windows Terminal doesn't know what directory your shell is in - it can't know because your shell needs to tell it! Remember that Terminal, a Console, a Shell, and a Prompt are different things. When you press `Alt+Shift+-` to split horizontally or `Ctrl+Shift+D` to duplicate a tab, the new shell starts fresh in `~` or `C:\Users\YourName`.

This is frustrating when you're deep in a project folder or using an Agent and want a second terminal right there in the current directory.

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

# Restart your terminal, then use:
#   Alt+Shift+-    → horizontal split (same directory)
#   Alt+Shift++    → vertical split (same directory)
#   Ctrl+Shift+D   → duplicate tab (same directory)

# Optional: Add GitHub Copilot CLI integration
.\Fix-SplitPanePersistence.ps1 -Copilot
#   Then type 'spc' to split pane + launch Copilot in current directory
```

## What It Does

### 1. PowerShell Profile (`$PROFILE`)
- Creates your profile if it doesn't exist
- Ensures Oh My Posh is initialized with `oh-my-posh init pwsh --config '<theme>' | Invoke-Expression`
- Comments out any custom `function prompt { }` blocks that would override Oh My Posh (with backup)
- Comments out duplicate Oh My Posh init lines if present

### 2. Oh My Posh Theme (if installed)
- **Checks your Oh My Posh version** and warns if it's older than v3.151.0 (minimum required for `pwd: osc99`)
- Locates your active theme from the profile
- Adds `"pwd": "osc99"` to the theme's root JSON object
- If the theme is in the built-in themes folder, copies it to `%LOCALAPPDATA%\oh-my-posh\themes` first (so updates don't overwrite your changes)
- Prompts for confirmation if your version is incompatible to prevent breaking your setup

### 2b. No Oh My Posh? No problem!
If Oh My Posh isn't installed, the script adds a `prompt` function to your profile that emits the [OSC 9;9 escape sequence](https://learn.microsoft.com/en-us/windows/terminal/tutorials/new-tab-same-directory#powershell-powershellexe-or-pwshexe) directly. This tells Windows Terminal your current directory without needing OMP.

### 3. Windows Terminal Settings
- Adds or updates keybindings in `settings.json`:

| Shortcut | Action |
|----------|--------|
| `Alt+Shift+-` | Split pane horizontally (same directory) |
| `Alt+Shift++` | Split pane vertically (same directory) |
| `Ctrl+Shift+D` | Duplicate tab (same directory) |

> **Note:** These are Windows Terminal's default shortcuts. The script updates them to use `splitMode: duplicate` so they preserve your directory. If you've customized these keybindings, the script will update your existing bindings rather than creating duplicates. Your other custom actions are preserved.

### Bonus: GitHub Copilot CLI Integration

Run with `-Copilot` to add a helper function to your PowerShell profile:

```powershell
.\Fix-SplitPanePersistence.ps1 -Copilot
```

This adds `Split-Copilot` (alias: `spc`) to your profile. After restarting your terminal:

```powershell
spc   # Splits pane and launches Copilot CLI in your current directory
```

> **Why a function instead of a keybinding?** Windows Terminal can't combine `splitMode: duplicate` (for directory inheritance) with a custom `commandline`. The `spc` function works around this by using `wt split-pane -d "$PWD"` to explicitly pass the current directory.

This opens [GitHub Copilot CLI](https://github.com/github/gh-copilot) in a new pane, right where you're working.

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
| `-Copilot` | Adds `Split-Copilot` function (alias: `spc`) to your profile for launching Copilot CLI in a split pane. |

## Safety Features

- **Version Check**: Detects your Oh My Posh version and warns if it's incompatible (< v3.151.0) before making changes
- **Backups**: Every modified file gets a timestamped backup (e.g., `settings.json.bak-20240115-143022-789`)
- **Idempotent**: Safe to run multiple times. Re-running when already configured makes no changes.
- **Graceful degradation**: If Oh My Posh isn't installed, the script adds an OSC 9;9 prompt function to your profile instead.

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
- Oh My Posh v3.151.0+ (optional - script adds fallback prompt if not installed)
  - **Note**: Current Oh My Posh versions are v11+. The v3.151.0 minimum refers to the feature support for `pwd: osc99`, which was added before the version jump to v11.

### Oh My Posh Version Notice

This script modifies your Oh My Posh theme to add `"pwd": "osc99"`, which requires **Oh My Posh v3.151.0 or newer** (all v11+ versions are supported). If you have an older version, the script will:

1. Detect your current version
2. Display a warning with upgrade instructions
3. Ask for confirmation before making changes
4. Skip Oh My Posh modifications if you decline

To check your version: `oh-my-posh --version`

To update:
```powershell
winget upgrade JanDeDobbeleer.OhMyPosh
```

## WSL Support

The Windows Terminal keybindings configured by this script work for WSL profiles too! The script automatically detects and fixes a common issue.

### Automatic WSL Profile Fix

By default, Windows Terminal may use the distro's launcher (e.g., `Ubuntu.exe`) which **does not pass the current working directory** to the shell. The script automatically detects this and fixes it by changing the profile to use `wsl.exe -d <distro>` instead.

```powershell
# The script will show this during a dry run:
What if: Performing the operation "Change commandline to 'wsl.exe -d Ubuntu-24.04'" on target "WSL profile 'Ubuntu-24.04'".
```

See [microsoft/terminal#3158](https://github.com/microsoft/terminal/issues/3158#issuecomment-2789336476) for why this is necessary.

### Configure Your Shell

Make sure your shell emits the OSC 9;9 escape sequence:

#### Option 1: Oh My Posh in WSL (recommended)

If you use Oh My Posh in WSL, just make sure your theme has `pwd: osc99` at the root level:

```json
{
  "version": 4,
  "pwd": "osc99",
  ...
}
```

Then init it in `~/.bashrc` (not `.profile` - bashrc runs for non-login shells like split panes):

```bash
eval "$(oh-my-posh init bash --config '~/your-theme.omp.json')"
```

Oh My Posh automatically handles the `wslpath` conversion for you.

#### Option 2: Without Oh My Posh

Add this to your `~/.bashrc`:

```bash
PROMPT_COMMAND=${PROMPT_COMMAND:+"$PROMPT_COMMAND; "}'printf "\e]9;9;%s\e\\" "$(wslpath -w "$PWD")"'
```

The `wslpath -w` converts Linux paths (`/home/user/project`) to Windows paths (`\\wsl$\Ubuntu\home\user\project`) so Windows Terminal can understand them.

#### For Zsh users

Add to `~/.zshrc`:

```zsh
keep_current_path() {
  printf "\e]9;9;%s\e\\" "$(wslpath -w "$PWD")"
}
precmd_functions+=(keep_current_path)
```

After editing your shell config, restart your terminal. Split panes and duplicate tabs will now preserve your WSL directory too.

## References

- [Microsoft Docs: New tab same directory](https://learn.microsoft.com/en-us/windows/terminal/tutorials/new-tab-same-directory#powershell-powershellexe-or-pwshexe) - Official tutorial on shell integration
- [Oh My Posh Discussion #1532](https://github.com/JanDeDobbeleer/oh-my-posh/discussions/1532) - Original discussion on OSC 99 support
- [Windows Terminal Shell Integration](https://learn.microsoft.com/en-us/windows/terminal/tutorials/shell-integration) - Deep dive on escape sequences
- [Oh My Posh pwd setting](https://ohmyposh.dev/docs/configuration/general#settings) - OSC 99/7/51 documentation

## License

MIT

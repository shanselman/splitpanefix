<#
.SYNOPSIS
    Configures PowerShell, Oh My Posh, and Windows Terminal for directory persistence in split panes and tabs.

.DESCRIPTION
    This script ensures:
    - PowerShell profile exists with proper Oh My Posh initialization
    - Oh My Posh theme emits directory info via OSC99
    - Windows Terminal keybindings preserve directory when splitting/duplicating

.PARAMETER WhatIf
    Shows what changes would be made without actually applying them.

.PARAMETER Verbose
    Enables detailed logging of all operations.

.PARAMETER ThemePath
    Optional custom path for the user-writable theme directory.

.PARAMETER Copilot
    Adds a keybinding (Ctrl+Shift+.) to split pane and launch GitHub Copilot CLI.

.EXAMPLE
    .\Fix-SplitPanePersistence.ps1
    
.EXAMPLE
    .\Fix-SplitPanePersistence.ps1 -WhatIf -Verbose

.EXAMPLE
    .\Fix-SplitPanePersistence.ps1 -Copilot
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$ThemePath,
    [switch]$Copilot
)

# Require PowerShell 7+
if ($PSVersionTable.PSVersion.Major -lt 7) {
    Write-Host ""
    Write-Host "  Whoa there! You're running PowerShell $($PSVersionTable.PSVersion)" -ForegroundColor Red
    Write-Host ""
    Write-Host "  This script requires PowerShell 7+, which is better in every way:" -ForegroundColor Yellow
    Write-Host "    - Faster" -ForegroundColor Gray
    Write-Host "    - Cross-platform" -ForegroundColor Gray
    Write-Host "    - Better error handling" -ForegroundColor Gray
    Write-Host "    - Modern JSON support" -ForegroundColor Gray
    Write-Host "    - Actually maintained" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  Install it:" -ForegroundColor Cyan
    Write-Host "    winget install Microsoft.PowerShell" -ForegroundColor White
    Write-Host ""
    Write-Host "  Then set PowerShell 7 as your default profile in Windows Terminal" -ForegroundColor Cyan
    Write-Host "  (Settings -> Startup -> Default profile -> PowerShell)" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  Then run: pwsh .\Fix-SplitPanePersistence.ps1" -ForegroundColor White
    Write-Host ""
    exit 1
}

$script:ChangesMode = $false

function Write-Log {
    param(
        [string]$Message,
        [switch]$Verbose
    )
    if ($Verbose -and $VerbosePreference -ne 'Continue') { return }
    $prefix = if ($WhatIfPreference) { "[DryRun] " } else { "" }
    Write-Host "$prefix$Message"
}

function Get-Timestamp {
    return (Get-Date -Format "yyyyMMdd-HHmmss-fff")
}

function Backup-File {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return $null }
    $backupPath = "$Path.bak-$(Get-Timestamp)"
    # Ensure unique backup path if one already exists
    $counter = 0
    while (Test-Path $backupPath) {
        $counter++
        $backupPath = "$Path.bak-$(Get-Timestamp)-$counter"
    }
    if ($WhatIfPreference) {
        Write-Log "Would backup: $Path -> $backupPath" -Verbose
        return $backupPath
    }
    Copy-Item -Path $Path -Destination $backupPath
    Write-Log "Backed up: $Path -> $backupPath" -Verbose
    return $backupPath
}

function Ensure-ProfileExists {
    $profilePath = $PROFILE.CurrentUserCurrentHost
    $profileDir = Split-Path $profilePath -Parent

    if (-not (Test-Path $profileDir)) {
        if ($PSCmdlet.ShouldProcess($profileDir, "Create directory")) {
            New-Item -ItemType Directory -Path $profileDir -Force | Out-Null
            Write-Log "Created profile directory: $profileDir"
        }
    }

    if (-not (Test-Path $profilePath)) {
        if ($PSCmdlet.ShouldProcess($profilePath, "Create empty profile")) {
            New-Item -ItemType File -Path $profilePath -Force | Out-Null
            Write-Log "Created PowerShell profile: $profilePath"
        }
    }

    return $profilePath
}

function Get-OMPInstalled {
    $omp = Get-Command oh-my-posh -ErrorAction SilentlyContinue
    return $null -ne $omp
}

function Get-OMPVersion {
    try {
        $versionOutput = oh-my-posh --version 2>&1
        if ($versionOutput -match '(\d+)\.(\d+)\.(\d+)') {
            return [version]"$($Matches[1]).$($Matches[2]).$($Matches[3])"
        }
        return $null
    }
    catch {
        return $null
    }
}

function Test-OMPVersionCompatible {
    param([version]$CurrentVersion)
    
    # Minimum version required for "pwd": "osc99" feature
    $minVersion = [version]"3.151.0"
    
    if ($null -eq $CurrentVersion) {
        return $false
    }
    
    return $CurrentVersion -ge $minVersion
}

function Show-OMPVersionWarning {
    param([version]$CurrentVersion)
    
    Write-Host ""
    Write-Host "  ⚠️  Oh My Posh Version Warning" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  Your Oh My Posh version: $CurrentVersion" -ForegroundColor White
    Write-Host "  Minimum required version: 3.151.0" -ForegroundColor White
    Write-Host ""
    Write-Host "  This script will add " -ForegroundColor Gray -NoNewline
    Write-Host '"pwd": "osc99"' -ForegroundColor Cyan -NoNewline
    Write-Host " to your Oh My Posh theme." -ForegroundColor Gray
    Write-Host "  This feature is only supported in Oh My Posh v3.151.0 and newer." -ForegroundColor Gray
    Write-Host ""
    Write-Host "  If you continue with an outdated version, your Oh My Posh may break!" -ForegroundColor Red
    Write-Host ""
    Write-Host "  To update Oh My Posh (recommended):" -ForegroundColor Cyan
    Write-Host "    winget upgrade JanDeDobbeleer.OhMyPosh" -ForegroundColor White
    Write-Host ""
    Write-Host "  Alternative (download and execute script from ohmyposh.dev):" -ForegroundColor Gray
    Write-Host "    Set-ExecutionPolicy Bypass -Scope Process -Force; " -ForegroundColor DarkGray -NoNewline
    Write-Host "Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://ohmyposh.dev/install.ps1'))" -ForegroundColor DarkGray
    Write-Host ""
}

function Get-OMPInitLines {
    param([string]$ProfileContent)
    $pattern = '^\s*oh-my-posh\s+init\s+pwsh\s+--config\s+[''"]?([^''"|\s]+)[''"]?\s*\|\s*Invoke-Expression'
    $matches = [regex]::Matches($ProfileContent, $pattern, [System.Text.RegularExpressions.RegexOptions]::Multiline)
    return $matches
}

function Get-ThemePathFromProfile {
    param([string]$ProfileContent)
    $pattern = "oh-my-posh\s+init\s+pwsh\s+--config\s+['""]?([^'""|\s]+)['""]?\s*\|\s*Invoke-Expression"
    if ($ProfileContent -match $pattern) {
        $themePath = $Matches[1]
        # Expand environment variables - handle %VAR% syntax
        $themePath = [System.Environment]::ExpandEnvironmentVariables($themePath)
        # Handle PowerShell variable syntax like $env:POSH_THEMES_PATH or $env:COMPUTERNAME
        while ($themePath -match '\$env:(\w+)') {
            $varName = $Matches[1]
            $varValue = [System.Environment]::GetEnvironmentVariable($varName)
            if ($varValue) {
                $themePath = $themePath -replace [regex]::Escape("`$env:$varName"), $varValue
            } else {
                break
            }
        }
        # Expand ~ to user profile
        if ($themePath.StartsWith('~')) {
            $themePath = $themePath -replace '^~', $env:USERPROFILE
        }
        return $themePath
    }
    return $null
}

function Fix-ProfileOMPInit {
    param([string]$ProfilePath)
    
    if (-not (Test-Path $ProfilePath)) { return $false }
    
    try {
        $content = Get-Content $ProfilePath -Raw -ErrorAction Stop
        if (-not $content) { $content = "" }
    $originalContent = $content
    $modified = $false

    # Comment out custom prompt functions
    $promptPattern = '(?ms)^(\s*function\s+prompt\s*\{.*?\n\})'
    if ($content -match $promptPattern) {
        Backup-File -Path $ProfilePath
        $content = [regex]::Replace($content, $promptPattern, @"
# [Fix-SplitPanePersistence] Commented out custom prompt to allow Oh My Posh
<#
`$1
#>
"@)
        $modified = $true
        Write-Log "Commented out custom prompt function in profile"
    }

    # Find all OMP init lines
    $initLines = Get-OMPInitLines -ProfileContent $content
    
    if ($initLines.Count -eq 0) {
        # No init line found - add one with default theme
        $defaultTheme = if ($env:POSH_THEMES_PATH) { 
            Join-Path $env:POSH_THEMES_PATH "jandedobbeleer.omp.json" 
        } else { 
            "~/.oh-my-posh/themes/jandedobbeleer.omp.json" 
        }
        $initLine = "`noh-my-posh init pwsh --config '$defaultTheme' | Invoke-Expression`n"
        $content += $initLine
        $modified = $true
        Write-Log "Added Oh My Posh init line to profile"
    }
    elseif ($initLines.Count -gt 1) {
        # Multiple init lines - comment out all but first
        if (-not $modified) { Backup-File -Path $ProfilePath }
        $first = $true
        foreach ($match in $initLines) {
            if ($first) { $first = $false; continue }
            $original = $match.Value
            $commented = "# [Fix-SplitPanePersistence] Duplicate init line commented out:`n# $original"
            $content = $content.Replace($original, $commented)
        }
        $modified = $true
        Write-Log "Commented out duplicate Oh My Posh init lines"
    }

    if ($modified -and $content -ne $originalContent) {
        if ($PSCmdlet.ShouldProcess($ProfilePath, "Update profile")) {
            Set-Content -Path $ProfilePath -Value $content -ErrorAction Stop
            $script:ChangesMode = $true
        }
        return $true
    }
    return $false
    }
    catch {
        Write-Log "Error updating profile: $_"
        return $false
    }
}

function Get-UserThemePath {
    param([string]$OriginalThemePath)
    
    $userThemeDir = if ($ThemePath) { $ThemePath } else { 
        Join-Path $env:LOCALAPPDATA "oh-my-posh\themes" 
    }
    
    if (-not (Test-Path $userThemeDir)) {
        if ($PSCmdlet.ShouldProcess($userThemeDir, "Create theme directory")) {
            New-Item -ItemType Directory -Path $userThemeDir -Force | Out-Null
            Write-Log "Created user theme directory: $userThemeDir" -Verbose
        }
    }
    
    $themeName = Split-Path $OriginalThemePath -Leaf
    return Join-Path $userThemeDir $themeName
}

function Ensure-ThemeIsWritable {
    param([string]$ProfilePath, [string]$CurrentThemePath)
    
    if (-not $CurrentThemePath -or -not (Test-Path $CurrentThemePath)) {
        Write-Log "Theme file not found: $CurrentThemePath" -Verbose
        return $null
    }
    
    # Check if theme is in built-in themes folder
    $poshThemesPath = $env:POSH_THEMES_PATH
    $isBuiltIn = $poshThemesPath -and $CurrentThemePath.StartsWith($poshThemesPath, [StringComparison]::OrdinalIgnoreCase)
    
    if ($isBuiltIn) {
        $userThemePath = Get-UserThemePath -OriginalThemePath $CurrentThemePath
        
        if ($PSCmdlet.ShouldProcess($CurrentThemePath, "Copy theme to user directory")) {
            Copy-Item -Path $CurrentThemePath -Destination $userThemePath -Force
            Write-Log "Copied theme to user directory: $userThemePath"
            
            # Update profile to use new theme path
            $profileContent = Get-Content $ProfilePath -Raw
            $escapedOld = [regex]::Escape($CurrentThemePath)
            # Also handle the $env: version
            $envPath = $CurrentThemePath.Replace($poshThemesPath, '$env:POSH_THEMES_PATH')
            $escapedEnvOld = [regex]::Escape($envPath)
            
            $newContent = $profileContent -replace $escapedOld, $userThemePath
            $newContent = $newContent -replace [regex]::Escape('$env:POSH_THEMES_PATH'), $userThemePath.Replace((Split-Path $userThemePath -Leaf), '').TrimEnd('\')
            
            if ($newContent -ne $profileContent) {
                Backup-File -Path $ProfilePath
                Set-Content -Path $ProfilePath -Value $newContent -NoNewline
                Write-Log "Updated profile to use user theme path"
            }
            $script:ChangesMode = $true
        }
        return $userThemePath
    }
    
    return $CurrentThemePath
}

function Update-ThemePwd {
    param([string]$ThemePath)
    
    if (-not $ThemePath -or -not (Test-Path $ThemePath)) {
        Write-Log "Cannot update theme - file not found: $ThemePath" -Verbose
        return $false
    }
    
    try {
        $themeContent = Get-Content $ThemePath -Raw
        $theme = $themeContent | ConvertFrom-Json -AsHashtable
        
        $currentPwd = $theme['pwd']
        if ($currentPwd -eq 'osc99') {
            Write-Log "Theme already has pwd: osc99" -Verbose
            return $false
        }
        
        $theme['pwd'] = 'osc99'
        
        if ($PSCmdlet.ShouldProcess($ThemePath, "Set pwd to osc99")) {
            Backup-File -Path $ThemePath
            $theme | ConvertTo-Json -Depth 100 | Set-Content -Path $ThemePath
            Write-Log "Updated theme with pwd: osc99"
            $script:ChangesMode = $true
        }
        return $true
    }
    catch {
        Write-Log "Error updating theme: $_"
        return $false
    }
}

function Find-TerminalSettings {
    $locations = @(
        # Packaged (Microsoft Store) version
        "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json"
        # Preview version
        "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe\LocalState\settings.json"
        # Unpackaged/portable version
        "$env:LOCALAPPDATA\Microsoft\Windows Terminal\settings.json"
    )
    
    foreach ($loc in $locations) {
        if (Test-Path $loc) {
            Write-Log "Found Windows Terminal settings: $loc" -Verbose
            return $loc
        }
    }
    return $null
}

function Update-TerminalActions {
    param([string]$SettingsPath)
    
    if (-not $SettingsPath -or -not (Test-Path $SettingsPath)) {
        Write-Log "Windows Terminal settings not found"
        return $false
    }
    
    try {
        $settingsContent = Get-Content $SettingsPath -Raw
        # Remove comments for parsing (Windows Terminal allows // comments)
        $cleanJson = $settingsContent -replace '(?m)^\s*//.*$', '' -replace ',(\s*[}\]])', '$1'
        $settings = $cleanJson | ConvertFrom-Json -AsHashtable
        
        # Validate settings structure
        if ($settings -isnot [hashtable] -and $settings -isnot [System.Collections.Specialized.OrderedDictionary]) {
            Write-Log "Windows Terminal settings has unexpected structure"
            return $false
        }
        
        if (-not $settings.ContainsKey('actions')) {
            $settings['actions'] = @()
        }
        
        # Check if using new format with separate keybindings array
        $useKeybindingsArray = $settings.ContainsKey('keybindings')
        
        $desiredActions = @(
            @{
                keys = 'alt+shift+minus'
                command = @{
                    action = 'splitPane'
                    split = 'horizontal'
                    splitMode = 'duplicate'
                }
            },
            @{
                keys = 'alt+shift+plus'
                command = @{
                    action = 'splitPane'
                    split = 'vertical'
                    splitMode = 'duplicate'
                }
            },
            @{
                keys = 'ctrl+shift+d'
                command = @{
                    action = 'duplicateTab'
                }
            }
        )
        
        # Add Copilot keybinding if requested - NOTE: This is handled via profile function instead
        # Windows Terminal can't combine splitMode:duplicate with commandline (directory inheritance breaks)
        
        $modified = $false
        
        if ($useKeybindingsArray) {
            # New Windows Terminal format: actions have IDs, keybindings reference them
            foreach ($desired in $desiredActions) {
                $actionId = "User.custom.$($desired.keys -replace '[+]', '')"
                
                # Check if keybinding exists
                $existingBinding = $settings['keybindings'] | Where-Object { $_.keys -eq $desired.keys }
                
                if (-not $existingBinding) {
                    # Add action with ID
                    $actionWithId = @{
                        command = $desired.command
                        id = $actionId
                    }
                    $settings['actions'] += $actionWithId
                    
                    # Add keybinding
                    $settings['keybindings'] += @{
                        keys = $desired.keys
                        id = $actionId
                    }
                    $modified = $true
                    Write-Log "Added action: $($desired.keys)" -Verbose
                }
                else {
                    # Check if the action needs updating (find action by ID)
                    $bindingId = $existingBinding.id
                    $existingAction = $settings['actions'] | Where-Object { $_.id -eq $bindingId }
                    
                    if ($existingAction) {
                        $needsUpdate = $false
                        if ($desired.command.splitMode -and $existingAction.command.splitMode -ne 'duplicate') {
                            $needsUpdate = $true
                        }
                        if ($needsUpdate) {
                            $existingAction.command = $desired.command
                            $modified = $true
                            Write-Log "Updated action: $($desired.keys)" -Verbose
                        }
                    }
                }
            }
        }
        else {
            # Old format: actions contain keys directly
            foreach ($desired in $desiredActions) {
                $existingIndex = -1
                for ($i = 0; $i -lt $settings['actions'].Count; $i++) {
                    $action = $settings['actions'][$i]
                    if ($action.keys -eq $desired.keys) {
                        $existingIndex = $i
                        break
                    }
                }
                
                if ($existingIndex -ge 0) {
                    $existing = $settings['actions'][$existingIndex]
                    $needsUpdate = $false
                    
                    if ($desired.command.splitMode) {
                        if ($existing.command -is [hashtable]) {
                            if ($existing.command.splitMode -ne 'duplicate') {
                                $needsUpdate = $true
                            }
                        } else {
                            $needsUpdate = $true
                        }
                    }
                    
                    if ($needsUpdate) {
                        $settings['actions'][$existingIndex] = $desired
                        $modified = $true
                        Write-Log "Updated action: $($desired.keys)" -Verbose
                    }
                }
                else {
                    $settings['actions'] += $desired
                    $modified = $true
                    Write-Log "Added action: $($desired.keys)" -Verbose
                }
            }
        }
        
        if ($modified) {
            if ($PSCmdlet.ShouldProcess($SettingsPath, "Update Windows Terminal actions")) {
                Backup-File -Path $SettingsPath
                $settings | ConvertTo-Json -Depth 100 | Set-Content -Path $SettingsPath
                Write-Log "Updated Windows Terminal settings"
                $script:ChangesMode = $true
            }
            return $true
        }
        else {
            Write-Log "Windows Terminal actions already configured" -Verbose
            return $false
        }
    }
    catch {
        Write-Log "Error updating Windows Terminal settings: $_"
        return $false
    }
}

# Main execution
Write-Log "Starting Fix-SplitPanePersistence..."

# Step 1: Ensure profile exists
$profilePath = Ensure-ProfileExists
Write-Log "Profile path: $profilePath" -Verbose

# Step 2: Check for Oh My Posh
$ompInstalled = Get-OMPInstalled

if ($ompInstalled) {
    Write-Log "Oh My Posh detected" -Verbose
    
    # Step 2a: Check Oh My Posh version
    $ompVersion = Get-OMPVersion
    $versionCompatible = Test-OMPVersionCompatible -CurrentVersion $ompVersion
    
    if ($ompVersion) {
        Write-Log "Oh My Posh version: $ompVersion" -Verbose
    }
    
    $proceedWithOMP = $true
    
    if (-not $versionCompatible) {
        Show-OMPVersionWarning -CurrentVersion $ompVersion
        
        # In WhatIf mode, just show the warning and proceed
        if ($WhatIfPreference) {
            Write-Host "  [DryRun] Would prompt for confirmation, but continuing in WhatIf mode" -ForegroundColor Gray
            Write-Host ""
        }
        else {
            # Prompt user for confirmation
            # Any response other than 'y' or 'Y' (including empty/Enter) is treated as "No" (safe default)
            $response = Read-Host "Do you want to continue anyway? This may break your Oh My Posh setup. (y/N)"
            if ($response -notmatch '^[Yy]') {
                Write-Host ""
                Write-Host "  Skipping Oh My Posh theme modifications." -ForegroundColor Yellow
                Write-Host "  Please update Oh My Posh and run this script again." -ForegroundColor Yellow
                Write-Host ""
                $proceedWithOMP = $false
            }
            else {
                Write-Host ""
                Write-Host "  Proceeding with Oh My Posh modifications..." -ForegroundColor Yellow
                Write-Host ""
            }
        }
    }
    
    if ($proceedWithOMP) {
        # Step 3: Fix profile OMP init
        $null = Fix-ProfileOMPInit -ProfilePath $profilePath
        
        # Step 4: Get and ensure writable theme
        $profileContent = Get-Content $profilePath -Raw
        $themePath = Get-ThemePathFromProfile -ProfileContent $profileContent
        Write-Log "Detected theme path: $themePath" -Verbose
        
        if ($themePath) {
            $writableThemePath = Ensure-ThemeIsWritable -ProfilePath $profilePath -CurrentThemePath $themePath
            
            # Step 5: Update theme pwd setting
            if ($writableThemePath) {
                $null = Update-ThemePwd -ThemePath $writableThemePath
            }
        }
        else {
            Write-Log "Could not detect theme path from profile"
        }
    }
}
else {
    Write-Log "Oh My Posh not installed - adding OSC 9;9 prompt function"
    
    # Add the prompt function that emits OSC 9;9 for directory tracking
    $profileContent = Get-Content $profilePath -Raw
    if (-not $profileContent) { $profileContent = "" }
    
    # Check if there's already an OSC 9;9 prompt or the marker
    if ($profileContent -notmatch 'OSC 9;9' -and $profileContent -notmatch '\[char\]27\]\]9;9') {
        $oscPromptFunction = @'

# OSC 9;9 - Tell Windows Terminal the current directory (for split pane directory inheritance)
# Added by Fix-SplitPanePersistence.ps1
function prompt {
    $loc = $executionContext.SessionState.Path.CurrentLocation
    $out = ""
    if ($loc.Provider.Name -eq "FileSystem") {
        $out += "$([char]27)]9;9;`"$($loc.ProviderPath)`"$([char]27)\"
    }
    $out += "PS $loc$('>' * ($nestedPromptLevel + 1)) "
    return $out
}
'@
        if ($PSCmdlet.ShouldProcess($profilePath, "Add OSC 9;9 prompt function")) {
            Backup-File -Path $profilePath
            Add-Content -Path $profilePath -Value $oscPromptFunction
            Write-Log "Added OSC 9;9 prompt function to profile"
            $script:ChangesMode = $true
        }
    }
    else {
        Write-Log "Profile already has OSC 9;9 prompt configuration" -Verbose
    }
}

# Step 6: Update Windows Terminal
$terminalSettings = Find-TerminalSettings
if ($terminalSettings) {
    $null = Update-TerminalActions -SettingsPath $terminalSettings
}
else {
    Write-Log "Windows Terminal settings not found - skipping Terminal configuration"
}

# Step 7: Add Copilot split function if requested
if ($Copilot) {
    $profileContent = Get-Content $profilePath -Raw
    if ($profileContent -notmatch 'Split-Copilot') {
        $copilotFunction = @'

# Split pane and launch GitHub Copilot CLI in current directory
function Split-Copilot {
    wt -w 0 split-pane -d "$PWD" pwsh -NoLogo -NoExit -Command "copilot"
}
Set-Alias -Name spc -Value Split-Copilot
'@
        if ($PSCmdlet.ShouldProcess($profilePath, "Add Split-Copilot function")) {
            Backup-File -Path $profilePath
            Add-Content -Path $profilePath -Value $copilotFunction
            Write-Log "Added Split-Copilot function (alias: spc) to profile"
            $script:ChangesMode = $true
        }
    }
    else {
        Write-Log "Split-Copilot function already in profile" -Verbose
    }
}

# Step 8: Check and fix WSL profiles for the Ubuntu.exe bug
if ($terminalSettings) {
    try {
        $settingsContent = Get-Content $terminalSettings -Raw
        $settings = $settingsContent | ConvertFrom-Json
        $wslProfiles = $settings.profiles.list | Where-Object { 
            $_.source -like "*WSL*" -or $_.source -like "*Ubuntu*" -or $_.name -like "*Ubuntu*" -or $_.name -like "*WSL*"
        }
        
        $wslFixed = $false
        
        foreach ($wslProfile in $wslProfiles) {
            # Skip if already using wsl.exe -d
            if ($wslProfile.commandline -match '^wsl(\.exe)?\s+-d\s+') {
                continue
            }
            
            # Check if using default launcher (no commandline) or Ubuntu.exe
            if (-not $wslProfile.commandline -or $wslProfile.commandline -match 'Ubuntu.*\.exe') {
                # Try to find matching distro name
                $distroName = $null
                $wslDistros = wsl -l -q 2>$null | Where-Object { $_ -and $_.Trim() }
                
                foreach ($distro in $wslDistros) {
                    $distro = $distro.Trim() -replace '\x00', ''  # Remove null chars from wsl output
                    if ($wslProfile.name -match [regex]::Escape($distro) -or $distro -match 'Ubuntu') {
                        $distroName = $distro
                        break
                    }
                }
                
                if ($distroName) {
                    $newCommandline = "wsl.exe -d $distroName"
                    
                    if ($PSCmdlet.ShouldProcess("WSL profile '$($wslProfile.name)'", "Change commandline to '$newCommandline'")) {
                        # Update the profile
                        $wslProfile | Add-Member -NotePropertyName 'commandline' -NotePropertyValue $newCommandline -Force
                        $wslFixed = $true
                        Write-Log "Fixed WSL profile '$($wslProfile.name)' to use: $newCommandline"
                    }
                }
            }
        }
        
        if ($wslFixed) {
            Backup-File -Path $terminalSettings
            $settings | ConvertTo-Json -Depth 100 | Set-Content -Path $terminalSettings
            $script:ChangesMode = $true
            Write-Host ""
            Write-Host "  WSL profiles updated to preserve directory on split!" -ForegroundColor Green
            Write-Host "  See: https://github.com/microsoft/terminal/issues/3158" -ForegroundColor Gray
            Write-Host ""
        }
    }
    catch {
        Write-Log "Could not check WSL profiles: $_" -Verbose
    }
}

# Summary
if ($WhatIfPreference) {
    Write-Log "Dry run complete - no changes were made"
}
elseif ($script:ChangesMode) {
    Write-Log "Done! Restart your terminal for changes to take effect."
}
else {
    Write-Log "Done! No changes were necessary - already configured."
}

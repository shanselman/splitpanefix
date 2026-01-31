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

.EXAMPLE
    .\Fix-SplitPanePersistence.ps1
    
.EXAMPLE
    .\Fix-SplitPanePersistence.ps1 -WhatIf -Verbose
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$ThemePath
)

$script:ChangesMode = $false

function Write-Log {
    param(
        [string]$Message,
        [switch]$Verbose
    )
    if ($Verbose -and -not $VerbosePreference -eq 'Continue') { return }
    $prefix = if ($WhatIfPreference) { "[DryRun] " } else { "" }
    Write-Host "$prefix$Message"
}

function Get-Timestamp {
    return (Get-Date -Format "yyyyMMdd-HHmmss")
}

function Backup-File {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return $null }
    $backupPath = "$Path.bak-$(Get-Timestamp)"
    if ($WhatIfPreference) {
        Write-Log "Would backup: $Path -> $backupPath" -Verbose
        return $backupPath
    }
    Copy-Item -Path $Path -Destination $backupPath -Force
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
    
    $content = Get-Content $ProfilePath -Raw
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
            Set-Content -Path $ProfilePath -Value $content -NoNewline
            $script:ChangesMode = $true
        }
        return $true
    }
    return $false
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
        
        if (-not $settings.ContainsKey('actions')) {
            $settings['actions'] = @()
        }
        
        $desiredActions = @(
            @{
                keys = 'alt+shift+-'
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
        
        $modified = $false
        
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
                
                # Check if splitMode is set correctly
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
else {
    Write-Log "Oh My Posh not installed - skipping OMP configuration"
}

# Step 6: Update Windows Terminal
$terminalSettings = Find-TerminalSettings
if ($terminalSettings) {
    $null = Update-TerminalActions -SettingsPath $terminalSettings
}
else {
    Write-Log "Windows Terminal settings not found - skipping Terminal configuration"
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

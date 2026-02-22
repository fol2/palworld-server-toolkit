#Requires -Version 5.1
<#
.SYNOPSIS
    Check and update UE4SS, Admin Commands mod, and PalworldSavePal (PSP).
.DESCRIPTION
    - UE4SS: GitHub API (Okaetsu/RE-UE4SS experimental-palworld release)
    - Admin Commands: CurseForge API (requires API key in config.json)
    - PSP: GitHub API (oMaN-Rod/palworld-save-pal latest release)
    - Backs up and restores Lua mods across UE4SS updates
    - Preserves AdminCommands config.lua across AdminCommands updates
    - Preserves PSP user data (backups, logs, psp.db) across PSP updates
    - Safe to call with server already stopped; never starts/stops the server itself
.PARAMETER Force
    Force reinstall of all components even if versions match.
#>
param(
    [switch]$Force
)

$ScriptDir       = Split-Path -Parent $MyInvocation.MyCommand.Path
$BaseDir         = Split-Path -Parent $ScriptDir
$Win64Dir        = "$BaseDir\server\Pal\Binaries\Win64"
$UE4SSDir        = "$Win64Dir\ue4ss"
$ModsDir         = "$UE4SSDir\Mods"
$LogDir          = "$BaseDir\logs"
$TempDir         = "$env:TEMP\palworld-update"
$ConfigFile      = "$BaseDir\config.json"

# Version tracking files
$UE4SSVersionFile   = "$LogDir\ue4ss-version.txt"
$AdminCmdVersionFile = "$LogDir\admincmd-version.txt"
$PSPVersionFile     = "$LogDir\psp-version.txt"

# Directories
$AdminCmdModDir  = "$ModsDir\AdminCommands"
$PSPDir          = "$BaseDir\tools\PalworldSavePal"

# URLs and IDs
$UE4SSGithubUrl    = "https://api.github.com/repos/Okaetsu/RE-UE4SS/releases/tags/experimental-palworld"
$AdminCmdModId     = 1328795
$AdminCmdCfUrl     = "https://www.curseforge.com/palworld/lua-code-mods/admin-commands"
$PSPGithubUrl      = "https://api.github.com/repos/oMaN-Rod/palworld-save-pal/releases/latest"

if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }
$LogFile = "$LogDir\mods-$(Get-Date -Format 'yyyy-MM').log"

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $line = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] [$Level] $Message"
    Add-Content -Path $LogFile -Value $line -Encoding UTF8
    Write-Host $line
}

# ── Load config ──────────────────────────────────────────────────────────────────
$CurseForgeApiKey = ""
if (Test-Path $ConfigFile) {
    try {
        $config = Get-Content $ConfigFile -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($config.curseforge_api_key) {
            $CurseForgeApiKey = $config.curseforge_api_key
        }
    } catch {
        Write-Log "Could not parse config.json: $_" -Level "WARN"
    }
}

# ═════════════════════════════════════════════════════════════════════════════════
# 1. UE4SS Update
# ═════════════════════════════════════════════════════════════════════════════════
Write-Log "=========================================="
Write-Log "  UE4SS / Mod / Tool Update Check"
Write-Log "=========================================="

try {
    Write-Log "Checking UE4SS (GitHub)..."
    $headers = @{ "User-Agent" = "palworld-server-updater/1.0" }
    $release = Invoke-RestMethod -Uri $UE4SSGithubUrl -Headers $headers -ErrorAction Stop

    $asset = $release.assets | Where-Object { $_.name -like "*ue4ss*.zip" } | Select-Object -First 1
    if (-not $asset) {
        $asset = $release.assets | Where-Object { $_.name -like "*.zip" } | Select-Object -First 1
    }
    if (-not $asset) {
        Write-Log "No zip asset found in UE4SS GitHub release." -Level "WARN"
    } else {
        $latestDateStr = ([datetime]$asset.updated_at).ToString("yyyy-MM-ddTHH:mm:ssZ")
        $installedDateStr = ""
        if (Test-Path $UE4SSVersionFile) {
            $installedDateStr = (Get-Content $UE4SSVersionFile -Raw -Encoding UTF8).Trim()
        }

        $dwapiExists = Test-Path "$Win64Dir\dwmapi.dll"
        $needsUpdate = $Force -or (-not $dwapiExists) -or ($installedDateStr -ne $latestDateStr)

        if (-not $needsUpdate) {
            Write-Log "UE4SS is up to date ($installedDateStr)."
        } else {
            if (-not $dwapiExists) {
                Write-Log "UE4SS not installed. Performing fresh install..."
            } else {
                Write-Log "UE4SS update available: $installedDateStr -> $latestDateStr"
            }

            # Prepare temp
            $ue4ssTmp = "$TempDir\ue4ss"
            if (Test-Path $ue4ssTmp) { Remove-Item $ue4ssTmp -Recurse -Force }
            New-Item -ItemType Directory -Path $ue4ssTmp -Force | Out-Null

            # Back up Mods folder
            $modsBackupDir = "$ue4ssTmp\Mods-backup"
            if (Test-Path $ModsDir) {
                Write-Log "Backing up Mods folder..."
                Copy-Item -Path $ModsDir -Destination $modsBackupDir -Recurse -Force
                $backedUp = (Get-ChildItem $modsBackupDir -ErrorAction SilentlyContinue).Name
                if ($backedUp) { Write-Log "  Backed up: $($backedUp -join ', ')" }
            }

            # Download
            $zipPath = "$ue4ssTmp\ue4ss.zip"
            Write-Log "Downloading UE4SS: $($asset.name) ($([math]::Round($asset.size/1MB, 1)) MB)..."
            Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $zipPath -UseBasicParsing
            Write-Log "Download complete."

            # Remove old UE4SS
            Remove-Item "$Win64Dir\dwmapi.dll"    -Force -ErrorAction SilentlyContinue
            Remove-Item "$Win64Dir\xinput1_3.dll" -Force -ErrorAction SilentlyContinue
            Remove-Item "$UE4SSDir"               -Recurse -Force -ErrorAction SilentlyContinue

            # Extract and find dwmapi.dll root
            $extractDir = "$ue4ssTmp\extract"
            New-Item -ItemType Directory -Path $extractDir -Force | Out-Null
            Expand-Archive -Path $zipPath -DestinationPath $extractDir -Force

            $dllFound = Get-ChildItem -Path $extractDir -Filter "dwmapi.dll" -Recurse | Select-Object -First 1
            if (-not $dllFound) {
                Write-Log "dwmapi.dll not found in zip. Aborting UE4SS update." -Level "ERROR"
            } else {
                $sourceDir = $dllFound.DirectoryName
                Write-Log "Installing UE4SS from: $sourceDir"
                Copy-Item -Path "$sourceDir\*" -Destination $Win64Dir -Recurse -Force

                # Apply required settings
                $settingsFile = "$UE4SSDir\UE4SS-settings.ini"
                if (Test-Path $settingsFile) {
                    $content = Get-Content $settingsFile -Raw -Encoding UTF8
                    $content = $content -replace '(?i)bUseUObjectArrayCache\s*=\s*true', 'bUseUObjectArrayCache = false'
                    Set-Content -Path $settingsFile -Value $content -Encoding UTF8
                    Write-Log "Applied: bUseUObjectArrayCache = false"
                }

                # Restore Mods
                if (Test-Path $modsBackupDir) {
                    Write-Log "Restoring mods from backup..."
                    if (-not (Test-Path $ModsDir)) {
                        New-Item -ItemType Directory -Path $ModsDir -Force | Out-Null
                    }
                    Get-ChildItem $modsBackupDir | ForEach-Object {
                        $dest = "$ModsDir\$($_.Name)"
                        if (Test-Path $dest) { Remove-Item $dest -Recurse -Force }
                        Copy-Item -Path $_.FullName -Destination $dest -Recurse -Force
                        Write-Log "  Restored: $($_.Name)"
                    }
                }

                $latestDateStr | Set-Content -Path $UE4SSVersionFile -Encoding UTF8
                Write-Log "UE4SS updated successfully ($latestDateStr)."
            }

            Remove-Item $ue4ssTmp -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
} catch {
    Write-Log "Failed to check/update UE4SS: $_" -Level "WARN"
}

# ═════════════════════════════════════════════════════════════════════════════════
# 2. Admin Commands Mod Update (CurseForge)
# ═════════════════════════════════════════════════════════════════════════════════
Write-Log "------------------------------------------"
if (-not $CurseForgeApiKey) {
    if (Test-Path $AdminCmdModDir) {
        Write-Log "Admin Commands mod: installed (no CurseForge API key - skipping update check)"
    } else {
        Write-Log "Admin Commands mod: NOT INSTALLED" -Level "WARN"
        Write-Log "  Download from: $AdminCmdCfUrl" -Level "WARN"
        Write-Log "  Set curseforge_api_key in config.json to enable auto-updates." -Level "WARN"
    }
} else {
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Write-Log "Checking Admin Commands mod (CurseForge)..."
        $cfHeaders = @{
            "x-api-key" = $CurseForgeApiKey
            "Accept"    = "application/json"
        }

        # Get latest file for the mod
        $r = Invoke-WebRequest -Uri "https://api.curseforge.com/v1/mods/$AdminCmdModId/files?pageSize=1" `
             -Headers $cfHeaders -UseBasicParsing -ErrorAction Stop
        $files = ($r.Content | ConvertFrom-Json).data
        if (-not $files -or $files.Count -eq 0) {
            Write-Log "No files found for Admin Commands mod." -Level "WARN"
        } else {
            $latestFile = $files[0]
            $latestFileId = $latestFile.id
            $latestFileName = $latestFile.fileName
            $latestDate = $latestFile.fileDate

            # Check installed version
            $installedFileId = ""
            if (Test-Path $AdminCmdVersionFile) {
                $installedFileId = (Get-Content $AdminCmdVersionFile -Raw -Encoding UTF8).Trim()
            }

            $needsUpdate = $Force -or (-not (Test-Path $AdminCmdModDir)) -or ($installedFileId -ne [string]$latestFileId)

            if (-not $needsUpdate) {
                Write-Log "Admin Commands mod is up to date (file ID: $installedFileId)."
            } else {
                if (-not (Test-Path $AdminCmdModDir)) {
                    Write-Log "Admin Commands mod: fresh install..."
                } else {
                    Write-Log "Admin Commands mod update: file $installedFileId -> $latestFileId ($latestDate)"
                }

                # Build CDN download URL: https://mediafilez.forgecdn.net/files/{first4}/{last3}/{filename}
                $fileIdStr = [string]$latestFileId
                $group1 = $fileIdStr.Substring(0, 4)
                $group2 = $fileIdStr.Substring(4).TrimStart('0')
                if (-not $group2) { $group2 = "0" }
                $cdnUrl = "https://mediafilez.forgecdn.net/files/$group1/$group2/$latestFileName"

                $acTmp = "$TempDir\admincmd"
                if (Test-Path $acTmp) { Remove-Item $acTmp -Recurse -Force }
                New-Item -ItemType Directory -Path $acTmp -Force | Out-Null

                # Back up config.lua (user's admin UID list)
                $configBackup = $null
                $configPath = "$AdminCmdModDir\Scripts\config.lua"
                if (Test-Path $configPath) {
                    $configBackup = "$acTmp\config.lua.bak"
                    Copy-Item -Path $configPath -Destination $configBackup -Force
                    Write-Log "  Backed up config.lua"
                }

                # Download
                $zipPath = "$acTmp\AdminCommands.zip"
                Write-Log "Downloading Admin Commands: $latestFileName from CDN..."
                Invoke-WebRequest -Uri $cdnUrl -OutFile $zipPath -UseBasicParsing -ErrorAction Stop
                Write-Log "Download complete."

                # Extract
                $extractDir = "$acTmp\extract"
                Expand-Archive -Path $zipPath -DestinationPath $extractDir -Force

                # Find the AdminCommands folder in the extracted contents
                $acFolder = Get-ChildItem -Path $extractDir -Directory -Recurse |
                            Where-Object { $_.Name -eq "AdminCommands" } |
                            Select-Object -First 1
                if (-not $acFolder) {
                    # Might be flat structure — check if Scripts dir exists at root
                    $scriptsDir = Get-ChildItem -Path $extractDir -Directory -Recurse |
                                  Where-Object { $_.Name -eq "Scripts" } |
                                  Select-Object -First 1
                    if ($scriptsDir) {
                        $acFolder = $scriptsDir.Parent
                    }
                }

                if (-not $acFolder) {
                    Write-Log "Could not find AdminCommands folder in zip. Aborting." -Level "ERROR"
                } else {
                    # Remove old mod, install new
                    if (Test-Path $AdminCmdModDir) {
                        Remove-Item $AdminCmdModDir -Recurse -Force
                    }
                    Copy-Item -Path $acFolder.FullName -Destination $AdminCmdModDir -Recurse -Force
                    Write-Log "Admin Commands installed to $AdminCmdModDir"

                    # Restore config.lua
                    if ($configBackup -and (Test-Path $configBackup)) {
                        Copy-Item -Path $configBackup -Destination $configPath -Force
                        Write-Log "  Restored config.lua (admin UIDs preserved)"
                    }

                    [string]$latestFileId | Set-Content -Path $AdminCmdVersionFile -Encoding UTF8
                    Write-Log "Admin Commands updated successfully (file ID: $latestFileId)."
                }

                Remove-Item $acTmp -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    } catch {
        Write-Log "Failed to check/update Admin Commands: $_" -Level "WARN"
        if (Test-Path $AdminCmdModDir) {
            Write-Log "Existing Admin Commands mod preserved." -Level "WARN"
        }
    }
}

# ═════════════════════════════════════════════════════════════════════════════════
# 3. PalworldSavePal (PSP) Update (GitHub)
# ═════════════════════════════════════════════════════════════════════════════════
Write-Log "------------------------------------------"
try {
    Write-Log "Checking PalworldSavePal (GitHub)..."
    $headers = @{ "User-Agent" = "palworld-server-updater/1.0" }
    $release = Invoke-RestMethod -Uri $PSPGithubUrl -Headers $headers -ErrorAction Stop

    $asset = $release.assets | Where-Object { $_.name -like "*windows-standalone*.zip" } | Select-Object -First 1
    if (-not $asset) {
        Write-Log "No windows-standalone zip found in PSP release." -Level "WARN"
    } else {
        $latestTag = $release.tag_name
        $installedTag = ""
        if (Test-Path $PSPVersionFile) {
            $installedTag = (Get-Content $PSPVersionFile -Raw -Encoding UTF8).Trim()
        }

        $needsUpdate = $Force -or (-not (Test-Path $PSPDir)) -or ($installedTag -ne $latestTag)

        if (-not $needsUpdate) {
            Write-Log "PalworldSavePal is up to date ($installedTag)."
        } else {
            if (-not (Test-Path $PSPDir)) {
                Write-Log "PalworldSavePal: fresh install..."
            } else {
                Write-Log "PalworldSavePal update: $installedTag -> $latestTag"
            }

            $pspTmp = "$TempDir\psp"
            if (Test-Path $pspTmp) { Remove-Item $pspTmp -Recurse -Force }
            New-Item -ItemType Directory -Path $pspTmp -Force | Out-Null

            # Back up user data (survives update)
            $preserveDirs = @("backups", "logs")
            $preserveFiles = @("psp.db")
            $userDataBackup = "$pspTmp\userdata"
            New-Item -ItemType Directory -Path $userDataBackup -Force | Out-Null

            if (Test-Path $PSPDir) {
                foreach ($dir in $preserveDirs) {
                    $src = "$PSPDir\$dir"
                    if (Test-Path $src) {
                        Copy-Item -Path $src -Destination "$userDataBackup\$dir" -Recurse -Force
                        Write-Log "  Backed up PSP\$dir"
                    }
                }
                foreach ($file in $preserveFiles) {
                    $src = "$PSPDir\$file"
                    if (Test-Path $src) {
                        Copy-Item -Path $src -Destination "$userDataBackup\$file" -Force
                        Write-Log "  Backed up PSP\$file"
                    }
                }
            }

            # Download
            $zipPath = "$pspTmp\psp.zip"
            Write-Log "Downloading PSP: $($asset.name) ($([math]::Round($asset.size/1MB, 1)) MB)..."
            Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $zipPath -UseBasicParsing
            Write-Log "Download complete."

            # Extract
            $extractDir = "$pspTmp\extract"
            Expand-Archive -Path $zipPath -DestinationPath $extractDir -Force

            # Find the root of the extracted PSP (directory containing PSP.exe)
            $pspExe = Get-ChildItem -Path $extractDir -Filter "PSP.exe" -Recurse | Select-Object -First 1
            if (-not $pspExe) {
                Write-Log "PSP.exe not found in zip. Aborting PSP update." -Level "ERROR"
            } else {
                $sourceDir = $pspExe.DirectoryName

                # Remove old PSP, install new
                $toolsDir = "$BaseDir\tools"
                if (-not (Test-Path $toolsDir)) {
                    New-Item -ItemType Directory -Path $toolsDir -Force | Out-Null
                }
                if (Test-Path $PSPDir) {
                    Remove-Item $PSPDir -Recurse -Force
                }
                Copy-Item -Path $sourceDir -Destination $PSPDir -Recurse -Force
                Write-Log "PSP installed to $PSPDir"

                # Restore user data
                foreach ($dir in $preserveDirs) {
                    $src = "$userDataBackup\$dir"
                    if (Test-Path $src) {
                        $dest = "$PSPDir\$dir"
                        if (Test-Path $dest) { Remove-Item $dest -Recurse -Force }
                        Copy-Item -Path $src -Destination $dest -Recurse -Force
                        Write-Log "  Restored PSP\$dir"
                    }
                }
                foreach ($file in $preserveFiles) {
                    $src = "$userDataBackup\$file"
                    if (Test-Path $src) {
                        Copy-Item -Path $src -Destination "$PSPDir\$file" -Force
                        Write-Log "  Restored PSP\$file"
                    }
                }

                $latestTag | Set-Content -Path $PSPVersionFile -Encoding UTF8
                Write-Log "PalworldSavePal updated successfully ($latestTag)."
            }

            Remove-Item $pspTmp -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
} catch {
    Write-Log "Failed to check/update PSP: $_" -Level "WARN"
}

# ═════════════════════════════════════════════════════════════════════════════════
Write-Log "=========================================="
Write-Log "  Update check complete."
Write-Log "=========================================="

#Requires -Version 5.1
<#
.SYNOPSIS
    Check and update UE4SS (Palworld fork) and preserve installed Lua mods.
.DESCRIPTION
    - Calls GitHub API to check Okaetsu/RE-UE4SS experimental-palworld release
    - Downloads and installs UE4SS if newer than installed version
    - Backs up and restores all mods in ue4ss\Mods\ across UE4SS updates
    - Warns if Admin Commands mod is not installed
    - Safe to call with server already stopped; never starts/stops the server itself
.PARAMETER Force
    Force reinstall of UE4SS even if version matches.
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
$VersionFile     = "$LogDir\ue4ss-version.txt"
$TempDir         = "$env:TEMP\palworld-ue4ss-update"
$GithubApiUrl    = "https://api.github.com/repos/Okaetsu/RE-UE4SS/releases/tags/experimental-palworld"
$AdminCmdModDir  = "$ModsDir\AdminCommands"
$AdminCmdUrl     = "https://www.curseforge.com/palworld/lua-code-mods/admin-commands"

if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }
$LogFile = "$LogDir\mods-$(Get-Date -Format 'yyyy-MM').log"

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $line = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] [$Level] $Message"
    Add-Content -Path $LogFile -Value $line -Encoding UTF8
    Write-Host $line
}

# ── UE4SS Update Check ────────────────────────────────────────────────────────
Write-Log "=========================================="
Write-Log "  UE4SS / Mod Update Check"
Write-Log "=========================================="

try {
    Write-Log "Calling GitHub API: $GithubApiUrl"
    $headers = @{ "User-Agent" = "palworld-server-updater/1.0" }
    $release = Invoke-RestMethod -Uri $GithubApiUrl -Headers $headers -ErrorAction Stop

    # Find the zip asset (prefer the one with ue4ss in name, fallback to any zip)
    $asset = $release.assets | Where-Object { $_.name -like "*ue4ss*.zip" } | Select-Object -First 1
    if (-not $asset) {
        $asset = $release.assets | Where-Object { $_.name -like "*.zip" } | Select-Object -First 1
    }
    if (-not $asset) {
        Write-Log "No zip asset found in UE4SS GitHub release." -Level "WARN"
        Write-Log "Skipping UE4SS update." -Level "WARN"
    } else {
        $latestDateStr = ([datetime]$asset.updated_at).ToString("yyyy-MM-ddTHH:mm:ssZ")
        $installedDateStr = ""
        if (Test-Path $VersionFile) {
            $installedDateStr = (Get-Content $VersionFile -Raw -Encoding UTF8).Trim()
        }

        $dwapiExists = Test-Path "$Win64Dir\dwmapi.dll"
        $needsUpdate = $Force -or (-not $dwapiExists) -or ($installedDateStr -ne $latestDateStr)

        if (-not $needsUpdate) {
            Write-Log "UE4SS is up to date (asset date: $installedDateStr). No update needed."
        } else {
            if (-not $dwapiExists) {
                Write-Log "UE4SS not installed. Performing fresh install..."
            } else {
                Write-Log "UE4SS update available."
                Write-Log "  Installed : $installedDateStr"
                Write-Log "  Latest    : $latestDateStr"
            }

            # Prepare temp directory
            if (Test-Path $TempDir) { Remove-Item $TempDir -Recurse -Force }
            New-Item -ItemType Directory -Path $TempDir -Force | Out-Null

            # Back up existing Mods folder (preserves Admin Commands etc. across UE4SS updates)
            $modsBackupDir = "$TempDir\Mods-backup"
            if (Test-Path $ModsDir) {
                Write-Log "Backing up Mods folder to temp..."
                Copy-Item -Path $ModsDir -Destination $modsBackupDir -Recurse -Force
                $backedUpMods = (Get-ChildItem $modsBackupDir -ErrorAction SilentlyContinue).Name
                if ($backedUpMods) {
                    Write-Log "  Backed up mods: $($backedUpMods -join ', ')"
                }
            }

            # Download UE4SS zip
            $zipPath = "$TempDir\ue4ss.zip"
            Write-Log "Downloading UE4SS: $($asset.name) ($([math]::Round($asset.size/1MB, 1)) MB)..."
            Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $zipPath -UseBasicParsing
            Write-Log "Download complete."

            # Remove old UE4SS files (leave server files untouched)
            Write-Log "Removing old UE4SS files..."
            Remove-Item "$Win64Dir\dwmapi.dll"    -Force -ErrorAction SilentlyContinue
            Remove-Item "$Win64Dir\xinput1_3.dll" -Force -ErrorAction SilentlyContinue  # old UE4SS artifact
            Remove-Item "$UE4SSDir"               -Recurse -Force -ErrorAction SilentlyContinue

            # Extract to temp, then find root with dwmapi.dll (handles zips with or without subfolder)
            $extractDir = "$TempDir\extract"
            New-Item -ItemType Directory -Path $extractDir -Force | Out-Null
            Expand-Archive -Path $zipPath -DestinationPath $extractDir -Force

            $dllFound = Get-ChildItem -Path $extractDir -Filter "dwmapi.dll" -Recurse |
                        Select-Object -First 1
            if (-not $dllFound) {
                Write-Log "dwmapi.dll not found in extracted UE4SS zip. Aborting update." -Level "ERROR"
            } else {
                $sourceDir = $dllFound.DirectoryName
                Write-Log "Installing UE4SS from: $sourceDir"
                Copy-Item -Path "$sourceDir\*" -Destination $Win64Dir -Recurse -Force
                Write-Log "UE4SS files installed to $Win64Dir"

                # Apply required settings
                $settingsFile = "$UE4SSDir\UE4SS-settings.ini"
                if (Test-Path $settingsFile) {
                    $content = Get-Content $settingsFile -Raw -Encoding UTF8
                    # Prevent crash on dedicated server
                    $content = $content -replace '(?i)bUseUObjectArrayCache\s*=\s*true', 'bUseUObjectArrayCache = false'
                    Set-Content -Path $settingsFile -Value $content -Encoding UTF8
                    Write-Log "Applied setting: bUseUObjectArrayCache = false"
                } else {
                    Write-Log "UE4SS-settings.ini not found at expected path; skipping settings patch." -Level "WARN"
                }

                # Restore backed-up Mods
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

                # Save installed version
                $latestDateStr | Set-Content -Path $VersionFile -Encoding UTF8
                Write-Log "UE4SS installed/updated successfully. Version date: $latestDateStr"
            }

            # Clean up temp
            Remove-Item $TempDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
} catch {
    Write-Log "Failed to check/update UE4SS: $_" -Level "WARN"
    Write-Log "Network issue or GitHub API unavailable. Server will start without mod update." -Level "WARN"
}

# ── Admin Commands Mod Check ──────────────────────────────────────────────────
Write-Log "------------------------------------------"
if (Test-Path $AdminCmdModDir) {
    Write-Log "Admin Commands mod: installed OK"
} else {
    Write-Log "Admin Commands mod: NOT INSTALLED" -Level "WARN"
    Write-Log "  To enable in-game item spawning, install the mod manually:" -Level "WARN"
    Write-Log "  1. Download from: $AdminCmdUrl" -Level "WARN"
    Write-Log "  2. Extract and place the mod folder here:" -Level "WARN"
    Write-Log "     $AdminCmdModDir" -Level "WARN"
    Write-Log "  3. The mod will be preserved automatically across future UE4SS updates." -Level "WARN"
}

Write-Log "=========================================="
Write-Log "  Mod update check complete."
Write-Log "=========================================="

#Requires -Version 5.1
<#
.SYNOPSIS
    Palworld Server Daily Update Script
.DESCRIPTION
    Stops the server (if running), runs SteamCMD update, then restarts.
    Designed to run daily at 04:00 via Task Scheduler (SYSTEM account).
    Uses a lock file so the watchdog in startup.ps1 does not restart
    the server mid-update.
#>

$ScriptDir   = Split-Path -Parent $MyInvocation.MyCommand.Path
$BaseDir     = Split-Path -Parent $ScriptDir
$ServerExe   = "$BaseDir\server\Pal\Binaries\Win64\PalServer-Win64-Shipping-Cmd.exe"
$SteamCMD    = "$BaseDir\steamcmd\steamcmd.exe"
$LogDir      = "$BaseDir\logs"
$LockFile    = "$LogDir\update.lock"
$ProcessName = "PalServer-Win64-Shipping-Cmd"

if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }
$LogFile = "$LogDir\daily-update-$(Get-Date -Format 'yyyy-MM').log"

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $line = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] [$Level] $Message"
    Add-Content -Path $LogFile -Value $line -Encoding UTF8
    Write-Host $line
}

Write-Log "=========================================="
Write-Log "  Palworld Daily Update"
Write-Log "=========================================="

# Skip if pause-updates.flag exists
$PauseFlag = "$LogDir\pause-updates.flag"
if (Test-Path $PauseFlag) {
    Write-Log "pause-updates.flag found - skipping update. Delete the flag to re-enable." -Level "WARN"
    exit 0
}

# Write lock so watchdog does not interfere
"Updating" | Set-Content -Path $LockFile -Encoding UTF8

try {
    # Stop server if running
    $proc = Get-Process -Name $ProcessName -ErrorAction SilentlyContinue
    $wasRunning = $null -ne $proc
    if ($wasRunning) {
        Write-Log "Stopping server for update (PID: $($proc.Id))..."
        $proc | Stop-Process -Force
        # Wait until the process is gone
        $timeout = 30
        while ((Get-Process -Name $ProcessName -ErrorAction SilentlyContinue) -and $timeout -gt 0) {
            Start-Sleep -Seconds 1
            $timeout--
        }
        Write-Log "Server stopped."
    } else {
        Write-Log "Server was not running."
    }

    # Run SteamCMD update
    if (-not (Test-Path $SteamCMD)) {
        Write-Log "SteamCMD not found: $SteamCMD" -Level "ERROR"
        exit 1
    }
    Write-Log "Running SteamCMD update (App ID 2394010)..."
    & $SteamCMD +force_install_dir "$BaseDir\server" +login anonymous +app_update 2394010 validate +quit
    Write-Log "Update complete (exit code: $LASTEXITCODE)."

    # Update UE4SS and mods
    Write-Log "Running mod update check..."
    & powershell.exe -ExecutionPolicy Bypass -File "$ScriptDir\update-mods.ps1"
    Write-Log "Mod update check done."

    # Restart server
    if ($wasRunning) {
        Write-Log "Restarting server..."
        Start-Process -FilePath $ServerExe -ArgumentList "-publiclobby" -WindowStyle Minimized
        Write-Log "Server restarted."
    }

} finally {
    # Always release lock
    Remove-Item -Path $LockFile -Force -ErrorAction SilentlyContinue
}

Write-Log "Daily update finished."

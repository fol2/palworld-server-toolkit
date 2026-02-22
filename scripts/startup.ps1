#Requires -Version 5.1
<#
.SYNOPSIS
    Palworld Server Startup Script
.DESCRIPTION
    On first run: updates the server via SteamCMD, then starts it.
    Afterwards: runs as a watchdog, restarting the server if it crashes.
    This script is designed to run indefinitely as a Task Scheduler task
    triggered at system startup (SYSTEM account, no execution time limit).
#>

$ScriptDir   = Split-Path -Parent $MyInvocation.MyCommand.Path
$BaseDir     = Split-Path -Parent $ScriptDir
$ServerExe   = "$BaseDir\server\Pal\Binaries\Win64\PalServer-Win64-Shipping-Cmd.exe"
$SteamCMD    = "$BaseDir\steamcmd\steamcmd.exe"
$LogDir      = "$BaseDir\logs"
$LockFile    = "$LogDir\update.lock"
$ProcessName = "PalServer-Win64-Shipping-Cmd"
$LiveEditorSc = "$ScriptDir\live-editor-server.ps1"

# Mod auto-disable (fast-crash detection)
$Win64Dir        = "$BaseDir\server\Pal\Binaries\Win64"
$ModDll          = "$Win64Dir\dwmapi.dll"
$ModDllDisabled  = "$Win64Dir\dwmapi.dll.disabled"
$ModDisabledFlag = "$LogDir\mod-disabled.flag"
$FastCrashWindow = 480  # seconds: crash within 8 min of start = fast crash
$FastCrashLimit  = 2    # disable mod after this many consecutive fast crashes

if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }
$LogFile = "$LogDir\startup-$(Get-Date -Format 'yyyy-MM').log"

# Prevent multiple instances of this watchdog
$mutex = New-Object System.Threading.Mutex($false, "Global\PalworldWatchdog")
if (-not $mutex.WaitOne(0)) {
    Write-Host "Another watchdog instance is already running. Exiting."
    exit 0
}

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $line = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] [$Level] $Message"
    Add-Content -Path $LogFile -Value $line -Encoding UTF8
    Write-Host $line
}

function Get-ServerProcess {
    Get-Process -Name $ProcessName -ErrorAction SilentlyContinue
}

function Start-PalServer {
    if (Get-ServerProcess) {
        Write-Log "Server is already running (PID: $((Get-ServerProcess).Id))."
        return
    }
    if (-not (Test-Path $ServerExe)) {
        Write-Log "Server executable not found: $ServerExe" -Level "ERROR"
        return
    }
    Write-Log "Starting Palworld server..."
    Start-Process -FilePath $ServerExe -ArgumentList "-publiclobby" -WindowStyle Minimized
    Start-Sleep -Seconds 5
    if (Get-ServerProcess) {
        Write-Log "Server started (PID: $((Get-ServerProcess).Id))."
    } else {
        Write-Log "Server process did not appear after launch." -Level "WARN"
    }
}

function Get-LiveEditorProcess {
    Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -like "*live-editor-server.ps1*" } |
        Select-Object -First 1
}

function Start-LiveEditor {
    if (Get-LiveEditorProcess) {
        Write-Log "Live Editor already running."
        return
    }
    if (-not (Test-Path $LiveEditorSc)) {
        Write-Log "Live Editor script not found: $LiveEditorSc" -Level "WARN"
        return
    }
    Write-Log "Starting Live Editor server..."
    Start-Process powershell.exe -ArgumentList "-ExecutionPolicy", "Bypass", "-File", $LiveEditorSc -WindowStyle Hidden
    Start-Sleep -Seconds 2
    if (Get-LiveEditorProcess) {
        Write-Log "Live Editor started."
    } else {
        Write-Log "Live Editor did not start." -Level "WARN"
    }
}

function Update-Server {
    if (-not (Test-Path $SteamCMD)) {
        Write-Log "SteamCMD not found: $SteamCMD" -Level "ERROR"
        return
    }
    Write-Log "Running SteamCMD update (App ID 2394010)..."
    # Signal that update is in progress (prevents watchdog restart during daily-update.ps1)
    "Updating" | Set-Content -Path $LockFile -Encoding UTF8
    try {
        & $SteamCMD +force_install_dir "$BaseDir\server" +login anonymous +app_update 2394010 validate +quit
        Write-Log "SteamCMD update complete (exit code: $LASTEXITCODE)."
    } finally {
        Remove-Item -Path $LockFile -Force -ErrorAction SilentlyContinue
    }
}

# ── Startup sequence ──────────────────────────────────────────────────────────
Write-Log "=========================================="
Write-Log "  Palworld Server Startup"
Write-Log "=========================================="

# Skip update if pause-updates.flag exists (e.g. when Xbox client lags behind Steam)
$PauseFlag = "$LogDir\pause-updates.flag"
if (Test-Path $PauseFlag) {
    Write-Log "pause-updates.flag found - skipping SteamCMD update." -Level "WARN"
    Write-Log "Delete $PauseFlag to re-enable auto-updates."
} else {
    Update-Server
}

# Update UE4SS and mods (runs after SteamCMD, before server start)
Write-Log "Running mod update check..."
& powershell.exe -ExecutionPolicy Bypass -File "$ScriptDir\update-mods.ps1"
Write-Log "Mod update check done."

Start-PalServer
Start-LiveEditor
$script:serverStartedAt = Get-Date
$script:fastCrashCount  = 0

# ── Watchdog loop (runs forever) ─────────────────────────────────────────────
Write-Log "Watchdog active. Checking server every 5 minutes..."
while ($true) {
    Start-Sleep -Seconds 300

    # Skip restart check if a daily update is in progress
    if (Test-Path $LockFile) {
        Write-Log "Update in progress, skipping watchdog check."
        continue
    }

    if (-not (Get-ServerProcess)) {
        # ── Fast-crash detection (possible mod crash) ──────────────────────
        $now       = Get-Date
        $uptimeSec = if ($script:serverStartedAt) {
            ($now - $script:serverStartedAt).TotalSeconds
        } else { 9999 }

        if ($uptimeSec -lt $FastCrashWindow) {
            $script:fastCrashCount++
            Write-Log ("Fast crash #{0} detected (perceived uptime: {1}s)." -f `
                $script:fastCrashCount, [int]$uptimeSec) -Level "WARN"

            if ($script:fastCrashCount -ge $FastCrashLimit `
                    -and (Test-Path $ModDll) `
                    -and (-not (Test-Path $ModDisabledFlag))) {
                Write-Log "AUTO-DISABLING mod after $($script:fastCrashCount) fast crashes." -Level "WARN"
                try {
                    if (Test-Path $ModDllDisabled) { Remove-Item $ModDllDisabled -Force }
                    Rename-Item -Path $ModDll -NewName "dwmapi.dll.disabled" -Force
                    "Auto-disabled at $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') after $($script:fastCrashCount) consecutive fast crashes." |
                        Set-Content $ModDisabledFlag -Encoding UTF8
                    Write-Log "dwmapi.dll renamed to .disabled. Re-enable via Monitor when ready." -Level "WARN"
                } catch {
                    Write-Log "Failed to rename mod DLL: $_" -Level "ERROR"
                }
                $script:fastCrashCount = 0
            }
        } else {
            if ($script:fastCrashCount -gt 0) {
                Write-Log "Server ran stably before crash. Resetting fast-crash counter."
                $script:fastCrashCount = 0
            }
        }
        # ──────────────────────────────────────────────────────────────────

        Write-Log "Server not running! Restarting..." -Level "WARN"
        Start-PalServer
        Start-LiveEditor
        $script:serverStartedAt = Get-Date
    }

    # ── Live Editor check ────────────────────────────────────────────────
    if (-not (Get-LiveEditorProcess)) {
        Write-Log "Live Editor not running. Restarting..." -Level "WARN"
        Start-LiveEditor
    }
}

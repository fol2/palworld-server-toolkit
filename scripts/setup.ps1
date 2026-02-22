#Requires -Version 5.1
#Requires -RunAsAdministrator
<#
.SYNOPSIS
    One-time setup for Palworld server automation.
.DESCRIPTION
    1. Checks prerequisites (git).
    2. Initialises git repository in SaveGames directory.
    3. Creates Task Scheduler tasks under the "\Palworld\" folder:
         Startup     - runs at boot, updates server, starts it, then watches forever
         DailyUpdate - runs daily at 04:00, updates server
         Backup      - runs every hour, commits SaveGames to git
    Run this script once as Administrator.
#>

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$BaseDir   = Split-Path -Parent $ScriptDir
$SaveDir   = "$BaseDir\server\Pal\Saved\SaveGames"
$LogDir    = "$BaseDir\logs"

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $colourMap = @{ INFO = "Cyan"; OK = "Green"; WARN = "Yellow"; ERROR = "Red" }
    if ($colourMap.ContainsKey($Level)) { $c = $colourMap[$Level] } else { $c = "White" }
    Write-Host "[$Level] $Message" -ForegroundColor $c
}

Write-Log "=========================================="
Write-Log "  Palworld Server Setup" "OK"
Write-Log "=========================================="

# -- 1. Prerequisites ----------------------------------------------------------
Write-Log "Checking prerequisites..."

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Log "git is not installed!" "ERROR"
    Write-Log "Download from: https://git-scm.com/download/win" "ERROR"
    Write-Log "After installing git, run this script again."
    exit 1
}
$gitVersion = (& git --version)
Write-Log "git: $gitVersion" "OK"

if (-not (Test-Path "$BaseDir\steamcmd\steamcmd.exe")) {
    Write-Log "SteamCMD not found at $BaseDir\steamcmd\steamcmd.exe" "WARN"
    Write-Log "Auto-update will not work until SteamCMD is placed there."
}

if (-not (Test-Path "$BaseDir\server\Pal\Binaries\Win64\PalServer-Win64-Shipping-Cmd.exe")) {
    Write-Log "Palworld server executable not found. Run SteamCMD update first." "WARN"
}

# -- 2. Create config.json from template ---------------------------------------
$configPath = "$BaseDir\config.json"
$configExample = "$BaseDir\config.example.json"
if (-not (Test-Path $configPath)) {
    if (Test-Path $configExample) {
        Copy-Item $configExample $configPath
        Write-Log "Created config.json from config.example.json — edit it with your settings." "WARN"
    } else {
        Write-Log "config.example.json not found — skipping config setup." "WARN"
    }
} else {
    Write-Log "config.json already exists." "OK"
}

# -- 3. Create directories -----------------------------------------------------
foreach ($dir in @($LogDir, $SaveDir)) {
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        Write-Log "Created: $dir"
    }
}

# -- 3. Git config for SYSTEM account ------------------------------------------
# Avoids "dubious ownership" errors when git runs as SYSTEM on files owned
# by a regular user account.
$gitConfigPath = "$ScriptDir\git-config"
$safeDirFwd    = $SaveDir.Replace('\', '/')

$gitConfigLines = @(
    "[user]",
    "    email = palworld-backup@localhost",
    "    name = Palworld Backup",
    "[safe]",
    "    directory = $safeDirFwd",
    "[core]",
    "    autocrlf = false"
)
$gitConfigLines | Set-Content -Path $gitConfigPath -Encoding UTF8
Write-Log "Created git config: $gitConfigPath" "OK"

# -- 4. Initialise git repo in SaveGames ---------------------------------------
$env:GIT_CONFIG_GLOBAL = $gitConfigPath

if (Test-Path "$SaveDir\.git") {
    Write-Log "Git repo already exists in SaveGames - skipping init." "OK"
} else {
    Write-Log "Initialising git repo in: $SaveDir"
    Push-Location $SaveDir

    # Try git init with branch name flag (git >= 2.28), fall back otherwise
    & git init -b main 2>$null
    if ($LASTEXITCODE -ne 0) {
        & git init
        & git symbolic-ref HEAD refs/heads/main
    }

    # Binary file attributes (stops git trying to diff/merge binary blobs)
    $gitattributes = @("*.sav    binary", "*.sav.bak binary")
    $gitattributes | Set-Content -Path ".gitattributes" -Encoding UTF8

    # Ignore temp files
    $gitignore = @("*.tmp", "*.lock")
    $gitignore | Set-Content -Path ".gitignore" -Encoding UTF8

    & git add -A
    $initMsg = "Initial backup: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    & git commit -m $initMsg 2>&1 | Out-Null

    Pop-Location
    Write-Log "Git repo initialised with initial commit." "OK"
}

# -- 5. Install LiveEditor mod -------------------------------------------------
$modSrc = "$BaseDir\mods\LiveEditor"
$modDst = "$BaseDir\server\Pal\Binaries\Win64\ue4ss\Mods\LiveEditor"
if (Test-Path $modSrc) {
    if (Test-Path "$BaseDir\server\Pal\Binaries\Win64\ue4ss") {
        if (-not (Test-Path $modDst)) {
            Copy-Item -Path $modSrc -Destination $modDst -Recurse
            Write-Log "Installed LiveEditor mod to UE4SS Mods directory." "OK"
        } else {
            Write-Log "LiveEditor mod already installed in UE4SS." "OK"
        }
    } else {
        Write-Log "UE4SS not installed yet — install UE4SS first, then re-run setup." "WARN"
    }
} else {
    Write-Log "mods\LiveEditor not found — skipping mod install." "WARN"
}

# -- 6. Task Scheduler tasks ---------------------------------------------------
Write-Log "Registering Task Scheduler tasks..."

$psh        = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
$psFlags    = "-ExecutionPolicy Bypass -NonInteractive -WindowStyle Hidden -File"
$taskFolder = "\Palworld\"
$principal  = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest

function Register-PalworldTask {
    param(
        [string]$Name,
        [string]$Script,
        $Trigger,
        [string]$Description
    )
    $action   = New-ScheduledTaskAction -Execute $psh `
                    -Argument "$psFlags `"$ScriptDir\$Script`""
    $settings = New-ScheduledTaskSettingsSet `
                    -MultipleInstances IgnoreNew `
                    -ExecutionTimeLimit ([System.TimeSpan]::Zero) `
                    -RestartCount 3 `
                    -RestartInterval (New-TimeSpan -Minutes 2) `
                    -StartWhenAvailable

    Register-ScheduledTask `
        -TaskName  "$taskFolder$Name" `
        -Action    $action `
        -Trigger   $Trigger `
        -Principal $principal `
        -Settings  $settings `
        -Description $Description `
        -Force | Out-Null

    Write-Log "Registered: $taskFolder$Name" "OK"
}

# Task A: Startup - update + start + watchdog loop (2-min delay after boot)
$bootTrigger = New-ScheduledTaskTrigger -AtStartup
$bootTrigger.Delay = "PT2M"
Register-PalworldTask "Startup" "startup.ps1" $bootTrigger `
    "Update and start Palworld server on boot, then monitor indefinitely."

# Task B: Daily update at 04:00
$dailyTrigger = New-ScheduledTaskTrigger -Daily -At "04:00AM"
Register-PalworldTask "DailyUpdate" "daily-update.ps1" $dailyTrigger `
    "Stop, update via SteamCMD, and restart Palworld server daily at 04:00."

# Task C: Hourly backup - schtasks.exe handles repetition triggers more reliably
Write-Log "Registering: ${taskFolder}Backup (hourly)..."
$backupScript = "$ScriptDir\backup.ps1"
$backupArg    = "$psFlags `"$backupScript`""
& schtasks.exe /create /tn "${taskFolder}Backup" /tr "`"$psh`" $backupArg" /sc HOURLY /mo 1 /ru SYSTEM /f 2>&1 | Out-Null

if ($LASTEXITCODE -eq 0) {
    Write-Log "Registered: ${taskFolder}Backup" "OK"
} else {
    Write-Log "schtasks failed to create Backup task - check Task Scheduler manually." "WARN"
}

# -- 6. Summary ----------------------------------------------------------------
Write-Log ""
Write-Log "=========================================="
Write-Log "  Setup Complete!" "OK"
Write-Log "=========================================="
Write-Log ""
Write-Log "Task Scheduler tasks created under '$taskFolder':"
Write-Log "  Startup     - runs at boot (2 min delay): update + start + watchdog"
Write-Log "  DailyUpdate - daily at 04:00: stop + update + restart"
Write-Log "  Backup      - every hour: git commit SaveGames"
Write-Log ""
Write-Log "Backup git repo : $SaveDir"
Write-Log "Log files       : $LogDir"
Write-Log ""
Write-Log "To start the server NOW without rebooting, run:"
Write-Log "  Start-ScheduledTask -TaskName '\Palworld\Startup'"
Write-Log ""
Write-Log "To view backup history:"
Write-Log "  cd `"$SaveDir`""
Write-Log "  git log --oneline"
Write-Log ""
Write-Log "To restore a save from a specific backup:"
Write-Log "  cd `"$SaveDir`""
Write-Log "  git log --oneline            # find the commit hash"
Write-Log "  git checkout <hash> -- .     # restore files (stop server first)"

#Requires -Version 5.1
<#
.SYNOPSIS
    Hourly robocopy snapshot of Palworld SaveGames (fully independent of git).
.DESCRIPTION
    Creates a timestamped copy of all player saves and world files.
    Keeps the most recent 48 snapshots (rolling 2-day window).
    Run as a separate Task Scheduler task (hourly) alongside backup.ps1.
    Excludes Palworld's own internal 'backup' subfolder to save disk space.
.NOTE
    This backup is immune to git operations - 'git checkout' cannot touch it.
    Always check here first when git backup is unavailable.
#>

$ScriptDir  = Split-Path -Parent $MyInvocation.MyCommand.Path
$BaseDir    = Split-Path -Parent $ScriptDir
$SaveDir    = "$BaseDir\server\Pal\Saved\SaveGames"
$BackupRoot = "$BaseDir\backups\hourly"
$LogDir     = "$BaseDir\logs"
$KeepCount  = 48   # 48 hourly = 2 days rolling

if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }
$LogFile = "$LogDir\backup-robocopy-$(Get-Date -Format 'yyyy-MM').log"

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $line = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] [$Level] $Message"
    Add-Content -Path $LogFile -Value $line -Encoding UTF8
    Write-Host $line
}

if (-not (Test-Path $SaveDir)) {
    Write-Log "SaveDir not found: $SaveDir" -Level "ERROR"
    exit 1
}

$timestamp = Get-Date -Format 'yyyy-MM-dd_HH-mm'
$dest = "$BackupRoot\$timestamp"
New-Item -ItemType Directory -Path $dest -Force | Out-Null

# Robocopy: mirror SaveGames excluding Palworld's internal backup folder (saves ~GB of space).
# Exit codes: 0=no changes, 1=copied OK, 2=extra files purged, 3=1+2; >=8 means error.
& robocopy $SaveDir $dest /MIR /XD backup /NFL /NDL /NJH /NJS /LOG+:NUL
$rc = $LASTEXITCODE
if ($rc -ge 8) {
    Write-Log "Robocopy failed (exit code $rc). Snapshot may be incomplete." -Level "ERROR"
    exit 1
}

$fileCount = (Get-ChildItem $dest -Recurse -File -ErrorAction SilentlyContinue).Count
Write-Log "Snapshot OK: $timestamp ($fileCount files, robocopy exit $rc)"

# Prune snapshots older than KeepCount
if (Test-Path $BackupRoot) {
    $allSnaps = Get-ChildItem $BackupRoot -Directory | Sort-Object Name -Descending
    $toDelete = $allSnaps | Select-Object -Skip $KeepCount
    foreach ($snap in $toDelete) {
        Remove-Item -Path $snap.FullName -Recurse -Force -ErrorAction SilentlyContinue
        Write-Log "Pruned old snapshot: $($snap.Name)"
    }
}

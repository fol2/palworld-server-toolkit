#Requires -Version 5.1
<#
.SYNOPSIS
    Health check and folder size analysis for Palworld server.
#>

$BaseDir = Split-Path -Parent $PSScriptRoot

Write-Host "=== SERVER PROCESS ===" -ForegroundColor Cyan
$proc = Get-Process -Name 'PalServer-Win64-Shipping-Cmd' -ErrorAction SilentlyContinue
if ($proc) {
    Write-Host "RUNNING  PID=$($proc.Id)  RAM=$([math]::Round($proc.WorkingSet/1MB))MB  Started=$($proc.StartTime)"
} else {
    Write-Host "NOT RUNNING" -ForegroundColor Red
}

Write-Host ""
Write-Host "=== SCHEDULED TASKS ===" -ForegroundColor Cyan
$taskNames = @('Startup','DailyUpdate','PalworldBackup-Robocopy','PalworldVSS-Daily','MareBackup')
foreach ($tn in $taskNames) {
    $t = Get-ScheduledTask -TaskName $tn -ErrorAction SilentlyContinue
    if ($t) {
        $lastRun = (Get-ScheduledTaskInfo -TaskName $tn -ErrorAction SilentlyContinue).LastRunTime
        Write-Host "  $($t.State.ToString().PadRight(8)) $tn  (last: $lastRun)"
    } else {
        Write-Host "  MISSING  $tn" -ForegroundColor Yellow
    }
}

Write-Host ""
Write-Host "=== RECENT BACKUP LOGS ===" -ForegroundColor Cyan
$gitLog = "$BaseDir\logs\backup-2026-02.log"
if (Test-Path $gitLog) {
    Write-Host "Git backup (last 5):"
    Get-Content $gitLog -Tail 5
}
$rcLog = "$BaseDir\logs\backup-robocopy-2026-02.log"
if (Test-Path $rcLog) {
    Write-Host "Robocopy backup (last 5):"
    Get-Content $rcLog -Tail 5
}

Write-Host ""
Write-Host "=== ROBOCOPY SNAPSHOTS ===" -ForegroundColor Cyan
$hourly = "$BaseDir\backups\hourly"
if (Test-Path $hourly) {
    $snaps = Get-ChildItem $hourly -Directory | Sort-Object Name -Descending
    Write-Host "  Count: $($snaps.Count)  (keep max 48)"
    Write-Host "  Newest: $($snaps[0].Name)"
    Write-Host "  Oldest: $($snaps[-1].Name)"
} else {
    Write-Host "  No snapshots found" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "=== VSS SHADOW COPIES ===" -ForegroundColor Cyan
& vssadmin list shadows /for=D: 2>&1 | Select-String 'creation time|Shadow Copy ID' | ForEach-Object { Write-Host "  $_" }

Write-Host ""
Write-Host "=== FOLDER SIZES ===" -ForegroundColor Cyan
Get-ChildItem $BaseDir -ErrorAction SilentlyContinue | ForEach-Object {
    if ($_.PSIsContainer) {
        $size = (Get-ChildItem $_.FullName -Recurse -File -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum
        $items = (Get-ChildItem $_.FullName -Recurse -File -ErrorAction SilentlyContinue).Count
        [PSCustomObject]@{
            Name   = $_.Name
            Type   = 'DIR'
            SizeMB = [math]::Round($size / 1MB, 0)
            Files  = $items
        }
    } else {
        [PSCustomObject]@{
            Name   = $_.Name
            Type   = 'FILE'
            SizeMB = [math]::Round($_.Length / 1MB, 1)
            Files  = 1
        }
    }
} | Sort-Object SizeMB -Descending | Format-Table -AutoSize

Write-Host "=== SERVER SUBFOLDER SIZES ===" -ForegroundColor Cyan
Get-ChildItem "$BaseDir\server" -ErrorAction SilentlyContinue | ForEach-Object {
    if ($_.PSIsContainer) {
        $size = (Get-ChildItem $_.FullName -Recurse -File -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum
        [PSCustomObject]@{
            Name   = $_.Name
            SizeMB = [math]::Round($size / 1MB, 0)
        }
    }
} | Sort-Object SizeMB -Descending | Format-Table -AutoSize

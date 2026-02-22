#Requires -Version 5.1
<#
.SYNOPSIS
    Enable Windows Shadow Copy (VSS) on D: with daily automatic snapshots.
.DESCRIPTION
    - Allocates up to 10 GB on D: for shadow copy storage.
    - Creates a scheduled task to take a new shadow copy daily at 02:30.
    - Keeps Windows' default retention (oldest auto-purged when storage fills).
    Run once as Administrator. Safe to re-run.
.NOTE
    Shadow Copy allows recovery via File Explorer > Properties > Previous Versions,
    or via: vssadmin list shadows /for=D:
#>

#Requires -RunAsAdministrator

$taskName = "PalworldVSS-Daily"
$ErrorActionPreference = "Stop"

Write-Host "Step 1: Configuring VSS shadow storage on D: (max 10 GB)..."
$vssOut = & vssadmin add shadowstorage /for=D: /on=D: /maxsize=10GB 2>&1
if ($LASTEXITCODE -ne 0 -and $vssOut -notmatch "already") {
    # "already" means it was set before — that's fine
    Write-Host "vssadmin output: $vssOut"
}
Write-Host "Storage configured."

Write-Host ""
Write-Host "Step 2: Taking an immediate shadow copy to verify VSS works on D:..."
try {
    $wmi    = [wmiclass]"\\.\root\cimv2:Win32_ShadowCopy"
    $result = $wmi.Create("D:\", "ClientAccessible")
    if ($result.ReturnValue -eq 0) {
        Write-Host "Shadow copy created OK. ID: $($result.ShadowID)"
    } else {
        Write-Host "Warning: shadow copy returned code $($result.ReturnValue). VSS may not be fully supported on D: (Storage Spaces)." -ForegroundColor Yellow
        Write-Host "Continuing with scheduled task setup anyway..."
    }
} catch {
    Write-Host "Warning: could not create shadow copy: $_" -ForegroundColor Yellow
    Write-Host "Continuing with scheduled task setup anyway..."
}

Write-Host ""
Write-Host "Step 3: Registering daily VSS Task Scheduler task ($taskName)..."

$psCmd = "(New-Object -ComObject Win32_ShadowCopy).Create('D:\', 'ClientAccessible')"
$action = New-ScheduledTaskAction `
    -Execute "powershell.exe" `
    -Argument "-NonInteractive -WindowStyle Hidden -Command `"$psCmd`""

$trigger  = New-ScheduledTaskTrigger -Daily -At "02:30"
$settings = New-ScheduledTaskSettingsSet `
    -ExecutionTimeLimit (New-TimeSpan -Minutes 15) `
    -MultipleInstances IgnoreNew
$principal = New-ScheduledTaskPrincipal `
    -UserId "SYSTEM" `
    -LogonType ServiceAccount `
    -RunLevel Highest

Register-ScheduledTask `
    -TaskName   $taskName `
    -Action     $action `
    -Trigger    $trigger `
    -Settings   $settings `
    -Principal  $principal `
    -Description "Daily D: shadow copy for Palworld save recovery (02:30)" `
    -Force | Out-Null

Write-Host "Scheduled task registered: $taskName (daily 02:30, SYSTEM)"
Write-Host ""
Write-Host "=== VSS SETUP COMPLETE ==="
Write-Host ""
Write-Host "Useful commands:"
Write-Host "  List shadow copies:   vssadmin list shadows /for=D:"
Write-Host "  Browse via Explorer:  right-click folder > Properties > Previous Versions"
Write-Host "  Manual snapshot:      (New-Object -ComObject Win32_ShadowCopy).Create('D:\', 'ClientAccessible')"

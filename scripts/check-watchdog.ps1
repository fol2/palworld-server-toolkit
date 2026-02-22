$procs = Get-WmiObject Win32_Process | Where-Object { $_.CommandLine -like '*startup.ps1*' }
if ($procs) {
    Write-Host "WATCHDOG RUNNING:"
    $procs | Select-Object ProcessId, CommandLine | Format-List
} else {
    Write-Host "No startup.ps1 process found"
}

Write-Host ""
Write-Host "Server:"
Get-Process -Name 'PalServer-Win64-Shipping-Cmd' -ErrorAction SilentlyContinue | Select-Object Id, StartTime, WorkingSet

#Requires -Version 5.1
param([string]$Path = 'D:\Coding\palworld-server')

function Get-FolderSize {
    param([string]$FolderPath)
    $files = Get-ChildItem $FolderPath -Recurse -File -ErrorAction SilentlyContinue
    [PSCustomObject]@{
        SizeBytes = ($files | Measure-Object Length -Sum).Sum
        FileCount = $files.Count
    }
}

Write-Host "=== CONTENTS OF: $Path ===" -ForegroundColor Cyan
Get-ChildItem $Path -ErrorAction SilentlyContinue | ForEach-Object {
    if ($_.PSIsContainer) {
        $info = Get-FolderSize $_.FullName
        [PSCustomObject]@{
            Name   = "[DIR]  $($_.Name)"
            SizeMB = [math]::Round($info.SizeBytes / 1MB, 0)
            Files  = $info.FileCount
        }
    } else {
        [PSCustomObject]@{
            Name   = "[FILE] $($_.Name)"
            SizeMB = [math]::Round($_.Length / 1MB, 1)
            Files  = 1
        }
    }
} | Sort-Object SizeMB -Descending | Format-Table Name, SizeMB, Files -AutoSize

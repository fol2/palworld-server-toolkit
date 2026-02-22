#Requires -Version 5.1
<#
.SYNOPSIS
    Shared configuration loader for Palworld Server Toolkit.
.DESCRIPTION
    Dot-source this file to get the Get-ToolkitConfig function,
    which reads config.json from the project root.
#>

function Get-ToolkitConfig {
    $configPath = Join-Path (Split-Path -Parent $PSScriptRoot) "config.json"
    if (Test-Path $configPath) {
        return Get-Content $configPath -Raw | ConvertFrom-Json
    }
    return $null
}

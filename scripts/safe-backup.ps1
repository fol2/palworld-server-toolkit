#Requires -Version 5.1
<#
.SYNOPSIS
    Pre-operation safety backup of all player saves and world files.
.DESCRIPTION
    Run this BEFORE any restore, git operation, or manual file change on saves.
    Creates a timestamped copy in backups\safe-backup\ AND a git commit.
    If robocopy fails, exits with code 1 — DO NOT proceed with the operation.
.NOTE
    Claude Code: this script MUST be run before any file operation on SaveGames.
    See CLAUDE.md for the mandatory pre-operation checklist.
#>

param(
    [string]$Reason = "manual"   # short description of why backup is being taken
)

$ScriptDir  = Split-Path -Parent $MyInvocation.MyCommand.Path
$BaseDir    = Split-Path -Parent $ScriptDir
$SaveDir    = "$BaseDir\server\Pal\Saved\SaveGames"
$BackupRoot = "$BaseDir\backups\safe-backup"
$LogDir     = "$BaseDir\logs"

if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $line = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] [$Level] $Message"
    Write-Host $line
}

Write-Log "=== SAFE BACKUP START (reason: $Reason) ==="

if (-not (Test-Path $SaveDir)) {
    Write-Log "SaveDir not found: $SaveDir" -Level "ERROR"
    exit 1
}

$timestamp = Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'
$dest = "$BackupRoot\$timestamp"
New-Item -ItemType Directory -Path $dest -Force | Out-Null

# Robocopy snapshot (independent of git)
& robocopy $SaveDir $dest /MIR /XD backup /NFL /NDL /NJH /NJS /LOG+:NUL
$rc = $LASTEXITCODE
if ($rc -ge 8) {
    Write-Log "ROBOCOPY FAILED (exit $rc). DO NOT proceed with the operation!" -Level "ERROR"
    exit 1
}

$fileCount = (Get-ChildItem $dest -Recurse -File -ErrorAction SilentlyContinue).Count
Write-Log "Robocopy snapshot OK: $dest ($fileCount files)"

# Git commit of current state (best-effort — failure does NOT block operation)
$env:GIT_CONFIG_GLOBAL = "$ScriptDir\git-config"
Push-Location $SaveDir
try {
    & git add -A 2>&1 | Out-Null
    $status = & git status --porcelain 2>&1
    if ($status) {
        & git commit -m "Safe backup: $Reason at $timestamp" 2>&1 | Out-Null
        Write-Log "Git commit: Safe backup: $Reason at $timestamp"
    } else {
        Write-Log "Git: working tree clean, nothing to commit."
    }
} catch {
    Write-Log "Git commit failed (non-fatal): $_" -Level "WARN"
} finally {
    Pop-Location
}

Write-Log "=== SAFE BACKUP COMPLETE. Safe to proceed. ==="
Write-Log "    Recovery path: $dest"

#Requires -Version 5.1
<#
.SYNOPSIS
    Palworld Save Game Backup Script
.DESCRIPTION
    Commits all changes in the SaveGames directory to git.
    Every Sunday, prunes git history older than 90 days to control
    repository size while keeping the full 90-day restore window.
    Designed to run hourly via Task Scheduler (SYSTEM account).
#>

$ScriptDir  = Split-Path -Parent $MyInvocation.MyCommand.Path
$BaseDir    = Split-Path -Parent $ScriptDir
$SaveDir    = "$BaseDir\server\Pal\Saved\SaveGames"
$LogDir     = "$BaseDir\logs"
$DaysToKeep = 90

# Point git at our custom config (avoids SYSTEM account safe.directory issues)
$env:GIT_CONFIG_GLOBAL = "$ScriptDir\git-config"

if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }
$LogFile = "$LogDir\backup-$(Get-Date -Format 'yyyy-MM').log"

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $line = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] [$Level] $Message"
    Add-Content -Path $LogFile -Value $line -Encoding UTF8
    Write-Host $line
}

# Pre-flight checks
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Log "git not found in PATH. Backup skipped." -Level "ERROR"
    exit 1
}
if (-not (Test-Path "$SaveDir\.git")) {
    Write-Log "No git repo found in $SaveDir. Run setup.ps1 first." -Level "ERROR"
    exit 1
}

Push-Location $SaveDir
try {

    # Commit changes
    & git add -A 2>&1 | Out-Null
    $status = & git status --porcelain 2>&1
    if ($status) {
        $commitMsg = "Backup $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
        & git commit -m $commitMsg 2>&1 | Out-Null
        Write-Log "Committed: $commitMsg"
    } else {
        Write-Log "No save changes since last backup."
    }

    # Weekly history pruning (runs every Sunday only)
    if ((Get-Date).DayOfWeek -ne 'Sunday') {
        return
    }

    Write-Log "Sunday: checking for history older than $DaysToKeep days..."

    $keepCommit = & git log --after="$DaysToKeep days ago" --reverse --format="%H" 2>$null |
                  Select-Object -First 1

    if (-not $keepCommit) {
        Write-Log "All commits are within $DaysToKeep days. Nothing to prune."
        return
    }

    # Check whether keepCommit has a parent (i.e., there IS older history)
    & git rev-parse "${keepCommit}^" 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Log "keepCommit is already the root. Nothing to prune."
        return
    }

    $currentBranch = & git rev-parse --abbrev-ref HEAD
    if ($currentBranch -eq "HEAD") {
        Write-Log "Detached HEAD state - skipping history pruning." -Level "WARN"
        return
    }

    Write-Log "Pruning commits older than $DaysToKeep days from branch '$currentBranch'..."

    # Create a new orphan root commit whose tree matches the state
    # just before keepCommit, so keepCommit's diff is still meaningful.
    $parentOfKeep = & git rev-parse "${keepCommit}^"
    $parentTree   = & git rev-parse "${parentOfKeep}^{tree}"

    $cutoffDate = (Get-Date).AddDays(-$DaysToKeep).ToString("yyyy-MM-dd")
    $env:GIT_AUTHOR_DATE    = "2000-01-01T00:00:00+00:00"
    $env:GIT_COMMITTER_DATE = "2000-01-01T00:00:00+00:00"
    $newRoot = (& git commit-tree $parentTree -m "Root commit (history before $cutoffDate pruned)").Trim()
    $env:GIT_AUTHOR_DATE    = $null
    $env:GIT_COMMITTER_DATE = $null

    if (-not $newRoot) {
        Write-Log "commit-tree failed. Skipping pruning." -Level "WARN"
        return
    }

    # Replay keepCommit..HEAD onto the new root
    $rebaseOut = & git rebase --onto $newRoot $parentOfKeep $currentBranch 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Log "Rebase failed. Aborting prune." -Level "WARN"
        Write-Log ($rebaseOut -join "`n") -Level "WARN"
        & git rebase --abort 2>$null
        return
    }

    # Remove rebase backup refs and compact the repository
    & git for-each-ref --format="delete %(refname)" refs/original/ 2>$null |
        & git update-ref --stdin 2>$null
    & git gc --prune=now --quiet 2>&1 | Out-Null

    Write-Log "History pruning complete. Oldest commit now within $DaysToKeep days."

} catch {
    $errMsg = $_.ToString()
    Write-Log "Unexpected error: $errMsg" -Level "ERROR"
} finally {
    Pop-Location
}

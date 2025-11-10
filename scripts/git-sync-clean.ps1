<#
.SYNOPSIS
    Sync local repo with origin/master and clean local branches.

.DESCRIPTION
    Performs a safe fast-forward sync of the local main branch (default: master) to
    origin/master. It optionally resets generated `site/` artifacts (recommended)
    and deletes all local branches except the configured main branch.

.NOTES
    - Written for PowerShell (tested on Windows PowerShell / PowerShell Core).
    - The script runs Git commands; ensure `git` is on PATH and you run this from
      the repository root.

.PARAMETER DryRun
    If provided, show the planned git commands but do not execute them.

.PARAMETER MainBranch
    Name of the main branch to keep (default: master).

.PARAMETER ResetSite
    If set, restore tracked files under `site/` (safe to regenerate) before pulling.

.PARAMETER PruneRemotes
    If set, run `git fetch --all --prune` before pulling.

.EXAMPLE
    .\scripts\git-sync-clean.ps1 -DryRun

.EXAMPLE
    .\scripts\git-sync-clean.ps1 -MainBranch main -ResetSite -PruneRemotes
#>

param(
    [switch]$DryRun,
    [string]$MainBranch = 'master',
    [switch]$ResetSite = $true,
    [switch]$PruneRemotes = $true
)

function Run-Git {
    param($Args)
    $cmd = "git $Args"
    if ($DryRun) { Write-Host "DRYRUN: $cmd"; return 0 }
    Write-Host "> $cmd"
    $p = Start-Process -FilePath git -ArgumentList $Args -NoNewWindow -Wait -PassThru -RedirectStandardOutput stdout.txt -RedirectStandardError stderr.txt
    $out = Get-Content stdout.txt -Raw -ErrorAction SilentlyContinue
    $err = Get-Content stderr.txt -Raw -ErrorAction SilentlyContinue
    Remove-Item stdout.txt, stderr.txt -ErrorAction SilentlyContinue
    if ($p.ExitCode -ne 0) {
        Write-Error "Command failed: $cmd`n$err"
        return $p.ExitCode
    }
    if ($out) { Write-Host $out }
    return 0
}

if (-not (Test-Path .git)) {
    Write-Error "This script must be run from the repository root (contains .git)"
    exit 1
}

Write-Host "=== git-sync-clean: main=$MainBranch ResetSite=$ResetSite PruneRemotes=$PruneRemotes DryRun=$DryRun ==="

if ($ResetSite) {
    if (Test-Path site) {
        Write-Host "Restoring tracked files under 'site/' (git restore --worktree --staged -- site)"
        if (-not $DryRun) { git restore --worktree --staged -- site }
    }
    # Remove an untracked generated helper under site if present (common during builds)
    $generatedHelper = Join-Path -Path 'site' -ChildPath 'perfsonar/tools_scripts/perfSONAR-auto-enroll-psconfig.sh'
    if (Test-Path $generatedHelper) {
        if ($DryRun) { Write-Host "DRYRUN: Remove-Item -Force $generatedHelper" } else {
            Write-Host "Removing generated file: $generatedHelper"
            Remove-Item -Force $generatedHelper
        }
    }
}

if ($PruneRemotes) {
    $rc = Run-Git 'fetch --all --prune'
    if ($rc -ne 0) { exit $rc }
}

# Ensure we are on the main branch
$rc = Run-Git "checkout $MainBranch"
if ($rc -ne 0) { exit $rc }

# Fast-forward pull
$rc = Run-Git "pull --ff-only origin $MainBranch"
if ($rc -ne 0) {
    Write-Error "Failed to fast-forward $MainBranch from origin/$MainBranch. Resolve manually."
    exit $rc
}

# Delete local branches except main
Write-Host "Listing local branches..."
$branches = git branch --format='%(refname:short)' | ForEach-Object { $_.Trim() }
$toDelete = @()
foreach ($b in $branches) {
    if ($b -and $b -ne $MainBranch) { $toDelete += $b }
}

if ($toDelete.Count -eq 0) {
    Write-Host "No local branches to delete."
} else {
    Write-Host "Local branches to delete:`n  $(($toDelete -join "`n  "))"
    if ($DryRun) {
        foreach ($b in $toDelete) { Write-Host "DRYRUN: git branch -D $b" }
    } else {
        $ok = Read-Host "Delete these local branches? Type 'yes' to confirm"
        if ($ok -eq 'yes') {
            foreach ($b in $toDelete) {
                Write-Host "Deleting $b"
                git branch -D $b
            }
        } else { Write-Host "Aborted branch deletion." }
    }
}

Write-Host "Final status:"
git status -sb

Write-Host "git-sync-clean completed."

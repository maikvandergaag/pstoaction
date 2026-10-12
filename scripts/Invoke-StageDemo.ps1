#Requires -Version 7.0

<#
.SYNOPSIS
    Runs all three stages of the demo against the same repository, locally.

.DESCRIPTION
    The same story as .github/workflows/demo-stages.yml, without needing a
    runner or a network connection. Each stage runs in its own pwsh process
    so the real exit code is visible — which is the entire point of Stage 1.

.PARAMETER Sample
    Which fixture to check: 'bad' (default) or 'good'.

.PARAMETER Path
    Check an arbitrary repository instead of one of the fixtures.

.PARAMETER Stage
    Run a single stage instead of all three. Useful mid-presentation.

.EXAMPLE
    ./scripts/Invoke-StageDemo.ps1

.EXAMPLE
    ./scripts/Invoke-StageDemo.ps1 -Sample good

.EXAMPLE
    ./scripts/Invoke-StageDemo.ps1 -Path ~/src/some-other-repo -Stage 3
#>
[CmdletBinding()]
param(
    [ValidateSet('bad', 'good')]
    [string]$Sample = 'bad',

    [string]$Path,

    [ValidateSet('1', '2', '3', 'all')]
    [string]$Stage = 'all'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$target = if ($Path) { (Resolve-Path -LiteralPath $Path).Path } else { Join-Path $repoRoot 'sample-repos' $Sample }

if (-not (Test-Path -LiteralPath $target -PathType Container)) {
    throw "Repository '$target' does not exist."
}

function Write-Banner {
    param([string]$Title, [string]$Subtitle)

    Write-Host ''
    Write-Host ('─' * 72) -ForegroundColor DarkGray
    Write-Host " $Title" -ForegroundColor Cyan
    if ($Subtitle) { Write-Host " $Subtitle" -ForegroundColor DarkGray }
    Write-Host ('─' * 72) -ForegroundColor DarkGray
}

function Invoke-Stage {
    <#
        Runs a stage in a child process so $LASTEXITCODE is the real thing a
        runner would see, not whatever the current session happens to hold.
    #>
    param([string[]]$Arguments, [hashtable]$Environment = @{})

    $previous = @{}
    foreach ($key in $Environment.Keys) {
        $previous[$key] = [Environment]::GetEnvironmentVariable($key)
        [Environment]::SetEnvironmentVariable($key, $Environment[$key])
    }

    try {
        # Out-Host, so the child's output goes straight to the console
        # instead of becoming this function's return value.
        & pwsh -NoProfile @Arguments | Out-Host
        return $LASTEXITCODE
    }
    finally {
        foreach ($key in $previous.Keys) {
            [Environment]::SetEnvironmentVariable($key, $previous[$key])
        }
    }
}

function Read-ActionOutput {
    <#
        Parses a $GITHUB_OUTPUT file, including the name<<delimiter form that
        multi-line values use.
    #>
    param([string]$LiteralPath)

    $outputs = [ordered]@{}
    $lines = @(Get-Content -LiteralPath $LiteralPath)

    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^(?<name>[^=<]+)<<(?<delimiter>.+)$') {
            $name = $Matches.name
            $delimiter = $Matches.delimiter
            $value = [System.Collections.Generic.List[string]]::new()

            $i++
            while ($i -lt $lines.Count -and $lines[$i] -ne $delimiter) {
                $value.Add($lines[$i])
                $i++
            }

            $outputs[$name] = $value -join "`n"
        }
        elseif ($lines[$i] -match '^(?<name>[^=]+)=(?<value>.*)$') {
            $outputs[$Matches.name] = $Matches.value
        }
    }

    $outputs
}

Write-Host ''
Write-Host "Checking: $target" -ForegroundColor White

$results = [ordered]@{}

# --- Stage 1 ---------------------------------------------------------------

if ($Stage -in '1', 'all') {
    Write-Banner -Title 'Stage 1 — a script someone copied' `
        -Subtitle 'Hard-coded values. No inputs, no outputs, no exit code.'

    Push-Location $target
    try {
        $exit = Invoke-Stage -Arguments @('-File', (Join-Path $repoRoot 'stages' '01-script' 'check-repo.ps1'))
    }
    finally {
        Pop-Location
    }

    $results['Stage 1'] = [pscustomobject]@{
        ExitCode = $exit
        Outcome  = if ($exit -eq 0) { 'success' } else { 'failure' }
        Detail   = 'no machine-readable result'
    }

    Write-Host ''
    Write-Host "  Exit code: $exit" -ForegroundColor $(if ($exit -eq 0) { 'Yellow' } else { 'Red' })
    if ($exit -eq 0) {
        Write-Host '  A pipeline calling this is green, whatever the script found.' -ForegroundColor Yellow
    }
}

# --- Stage 2 ---------------------------------------------------------------

if ($Stage -in '2', 'all') {
    Write-Banner -Title 'Stage 2 — the same script, with a contract' `
        -Subtitle 'Inputs, outputs and a real exit code. Still one untestable file.'

    # The action writes outputs to $GITHUB_OUTPUT, so point it at a temp file
    # to see exactly what a workflow would receive.
    $outputFile = Join-Path ([IO.Path]::GetTempPath()) "stage2_$([guid]::NewGuid().ToString('N')).txt"
    New-Item -ItemType File -Path $outputFile -Force | Out-Null

    $exit = Invoke-Stage -Environment @{ GITHUB_OUTPUT = $outputFile } -Arguments @(
        '-File', (Join-Path $repoRoot 'stages' '02-composite' 'check-repo.ps1')
        '-Path', $target
        '-RequiredFiles', 'README.md,LICENSE,.gitignore'
        '-RequiredReadmeSections', 'Usage'
    )

    $outputs = Read-ActionOutput -LiteralPath $outputFile
    Remove-Item -LiteralPath $outputFile -Force

    $results['Stage 2'] = [pscustomobject]@{
        ExitCode = $exit
        Outcome  = if ($exit -eq 0) { 'success' } else { 'failure' }
        Detail   = "checks-failed=$($outputs['checks-failed']) — a count, not the reasons"
    }

    Write-Host ''
    Write-Host "  Exit code: $exit"
    Write-Host '  Outputs a caller receives:'
    foreach ($name in $outputs.Keys) { Write-Host "    $name=$($outputs[$name])" }
}

# --- Stage 3 ---------------------------------------------------------------

if ($Stage -in '3', 'all') {
    Write-Banner -Title 'Stage 3 — the shared action' `
        -Subtitle 'Logic split out, unit tested, structured output, versioned.'

    $outputFile = Join-Path ([IO.Path]::GetTempPath()) "stage3_$([guid]::NewGuid().ToString('N')).txt"
    $summaryFile = Join-Path ([IO.Path]::GetTempPath()) "stage3_summary_$([guid]::NewGuid().ToString('N')).md"
    New-Item -ItemType File -Path $outputFile -Force | Out-Null
    New-Item -ItemType File -Path $summaryFile -Force | Out-Null

    $exit = Invoke-Stage -Environment @{ GITHUB_OUTPUT = $outputFile; GITHUB_STEP_SUMMARY = $summaryFile } -Arguments @(
        '-File', (Join-Path $repoRoot 'scripts' 'Invoke-RepoStandardsCheck.ps1')
        '-Path', $target
        '-RequiredFile', "README.md`nLICENSE`n.gitignore"
        '-RequiredReadmeSection', 'Usage'
        '-ForbiddenPattern', "*.pfx`n*.pem"
    )

    $outputs = Read-ActionOutput -LiteralPath $outputFile
    $report = if ($outputs['report-json']) { $outputs['report-json'] | ConvertFrom-Json } else { $null }

    Write-Host ''
    Write-Host "  Exit code: $exit"
    Write-Host '  Job summary that a workflow would render:' -ForegroundColor DarkGray
    Get-Content -LiteralPath $summaryFile | ForEach-Object { Write-Host "    $_" -ForegroundColor DarkGray }

    if ($report) {
        $failedChecks = @($report.Checks | Where-Object { -not $_.Passed })
        if ($failedChecks.Count -gt 0) {
            Write-Host ''
            Write-Host '  And the same result as data, so a caller can act on it:'
            foreach ($check in $failedChecks) {
                Write-Host "    [$($check.Category)] $($check.Name) — $($check.Message)" -ForegroundColor Red
            }
        }
    }

    Remove-Item -LiteralPath $outputFile, $summaryFile -Force

    $results['Stage 3'] = [pscustomobject]@{
        ExitCode = $exit
        Outcome  = if ($exit -eq 0) { 'success' } else { 'failure' }
        Detail   = if ($report) { "$($report.Failed) of $($report.Total) failed, each one named" } else { 'structured JSON' }
    }
}

# --- Comparison ------------------------------------------------------------

if ($Stage -eq 'all') {
    Write-Banner -Title 'The comparison'

    $results.GetEnumerator() |
        ForEach-Object {
            [pscustomobject]@{
                Stage    = $_.Key
                Exit     = $_.Value.ExitCode
                Pipeline = $_.Value.Outcome
                'What a caller gets' = $_.Value.Detail
            }
        } |
        Format-Table -AutoSize |
        Out-Host

    if ($results['Stage 1'].ExitCode -eq 0 -and $results['Stage 3'].ExitCode -ne 0) {
        Write-Host 'Same repository. Stage 1 kept the pipeline green; Stage 3 failed it and said why.' -ForegroundColor Yellow
        Write-Host ''
    }
}

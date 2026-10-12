#Requires -Version 7.0

<#
.SYNOPSIS
    Entry point for the Repo Standards Check action.

.DESCRIPTION
    This script is the boundary between GitHub Actions and the checking
    logic. It parses inputs, calls the RepoStandards module, and translates
    the result into outputs, a job summary and an exit code.

    All of the actual checking lives in src/RepoStandards/RepoStandards.psm1
    so that it can be unit tested without a workflow.

.EXAMPLE
    ./scripts/Invoke-RepoStandardsCheck.ps1 -Path . -RequiredFile 'README.md','LICENSE'
#>
[CmdletBinding()]
param(
    [string]$Path = '.',

    # Accepts newline- and/or comma-separated values, because that is what
    # action inputs look like after YAML is done with them.
    [string]$RequiredFile = '',

    [string]$RequiredReadmeSection = '',

    [string]$ForbiddenPattern = '',

    [ValidateSet('true', 'false')]
    [string]$FailOnError = 'true',

    [ValidateSet('true', 'false')]
    [string]$WriteJobSummary = 'true',

    [string]$ReportPath = ''
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

Write-Host "Initializing Repo Standards Check..."

Import-Module (Join-Path $PSScriptRoot '..' 'src' 'RepoStandards' 'RepoStandards.psm1') -Force

function ConvertFrom-ActionList {
    <#
    .SYNOPSIS
        Turns a multi-line or comma-separated action input into a string array.
    #>
    param([string]$Value)

    $items = @()

    if (-not [string]::IsNullOrWhiteSpace($Value)) {
        $items = @(
            $Value -split '[\r\n,]+' |
                ForEach-Object { $_.Trim() } |
                Where-Object { $_ -and -not $_.StartsWith('#') }
        )
    }

    # The leading comma matters. Without it PowerShell unrolls an empty array
    # to $null on return, and piping $null runs the loop body once with a null
    # value. That is a genuinely nasty bug to find later.
    return , [string[]]$items
}

function Set-ActionOutput {
    <#
    .SYNOPSIS
        Writes a step output, handling multi-line values safely.
    #>
    param([string]$Name, [string]$Value)

    if (-not $env:GITHUB_OUTPUT) { return }

    if ($Value -match '[\r\n]') {
        $delimiter = "ghadelim_$([guid]::NewGuid().ToString('N'))"
        Add-Content -LiteralPath $env:GITHUB_OUTPUT -Value "$Name<<$delimiter"
        Add-Content -LiteralPath $env:GITHUB_OUTPUT -Value $Value
        Add-Content -LiteralPath $env:GITHUB_OUTPUT -Value $delimiter
    }
    else {
        Add-Content -LiteralPath $env:GITHUB_OUTPUT -Value "$Name=$Value"
    }
}

# --- Run -------------------------------------------------------------------

$summary = Invoke-RepoStandardsCheck `
    -Path $Path `
    -RequiredFile (ConvertFrom-ActionList $RequiredFile) `
    -RequiredReadmeSection (ConvertFrom-ActionList $RequiredReadmeSection) `
    -ForbiddenPattern (ConvertFrom-ActionList $ForbiddenPattern)

# --- Report ----------------------------------------------------------------

foreach ($check in $summary.Checks) {
    if ($check.Passed) {
        Write-Host "  ✅ $($check.Message)"
    }
    else {
        # Annotates the pull request, not just the log.
        Write-Host "::error title=Repo standards::$($check.Message)"
    }
}

Write-Host ''
Write-Host "$($summary.Passed)/$($summary.Total) checks passed."

$markdown = $summary | ConvertTo-MarkdownReport
$json = $summary | ConvertTo-Json -Depth 5 -Compress

if ($WriteJobSummary -eq 'true' -and $env:GITHUB_STEP_SUMMARY) {
    Add-Content -LiteralPath $env:GITHUB_STEP_SUMMARY -Value $markdown
}

if ($ReportPath) {
    $reportDir = Split-Path -Parent $ReportPath
    if ($reportDir -and -not (Test-Path -LiteralPath $reportDir)) {
        New-Item -ItemType Directory -Path $reportDir -Force | Out-Null
    }
    Set-Content -LiteralPath $ReportPath -Value $json -Encoding utf8
    Write-Host "Report written to $ReportPath"
}

# --- Outputs ---------------------------------------------------------------

Set-ActionOutput -Name 'result'        -Value $summary.Result
Set-ActionOutput -Name 'checks-total'  -Value $summary.Total
Set-ActionOutput -Name 'checks-passed' -Value $summary.Passed
Set-ActionOutput -Name 'checks-failed' -Value $summary.Failed
Set-ActionOutput -Name 'report-json'   -Value $json
Set-ActionOutput -Name 'report-path'   -Value $ReportPath

# --- Exit ------------------------------------------------------------------

if ($summary.Result -eq 'failed' -and $FailOnError -eq 'true') {
    exit 1
}

exit 0

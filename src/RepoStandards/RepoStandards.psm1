#Requires -Version 7.0

Set-StrictMode -Version Latest

<#
    RepoStandards

    Pure checking logic. This module knows nothing about GitHub Actions,
    environment variables or exit codes, which is exactly why it can be
    unit tested quickly and reliably.

    The Actions-specific plumbing lives in scripts/Invoke-RepoStandardsCheck.ps1.
#>

function New-CheckResult {
    <#
    .SYNOPSIS
        Creates a single check result.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][string]$Category,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][bool]$Passed,
        [Parameter(Mandatory)][string]$Message
    )

    [pscustomobject]@{
        Category = $Category
        Name     = $Name
        Passed   = $Passed
        Message  = $Message
    }
}

function Test-RequiredFile {
    <#
    .SYNOPSIS
        Verifies that each required file exists in the repository.

    .PARAMETER Path
        Root of the repository to inspect.

    .PARAMETER RequiredFile
        Repository-relative paths that must exist. Supports forward slashes
        on every platform.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject[]])]
    param(
        [Parameter(Mandatory)][string]$Path,
        [string[]]$RequiredFile = @()
    )

    foreach ($file in $RequiredFile) {
        if ([string]::IsNullOrWhiteSpace($file)) { continue }
        $relative = $file.Trim()

        $full = Join-Path -Path $Path -ChildPath $relative
        $exists = Test-Path -LiteralPath $full -PathType Leaf

        New-CheckResult -Category 'required-file' -Name $relative -Passed $exists -Message $(
            if ($exists) { "Found '$relative'." } else { "Required file '$relative' is missing." }
        )
    }
}

function Test-ReadmeSection {
    <#
    .SYNOPSIS
        Verifies that README.md contains the expected headings.

    .DESCRIPTION
        Matching is case-insensitive and accepts any heading level, so
        '## Usage' and '### Usage' both satisfy a requirement for 'Usage'.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject[]])]
    param(
        [Parameter(Mandatory)][string]$Path,
        [string[]]$RequiredSection = @(),
        [string]$ReadmeName = 'README.md'
    )

    $sections = @(
        $RequiredSection |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
            ForEach-Object { $_.Trim() }
    )
    if ($sections.Count -eq 0) { return }

    $readmePath = Join-Path -Path $Path -ChildPath $ReadmeName

    if (-not (Test-Path -LiteralPath $readmePath -PathType Leaf)) {
        foreach ($section in $sections) {
            New-CheckResult -Category 'readme-section' -Name $section -Passed $false `
                -Message "Cannot check section '$section' because '$ReadmeName' does not exist."
        }
        return
    }

    $content = Get-Content -LiteralPath $readmePath -Raw -ErrorAction Stop
    if ($null -eq $content) { $content = '' }

    foreach ($section in $sections) {
        $pattern = '(?im)^\s{0,3}#{1,6}\s+' + [regex]::Escape($section) + '\s*#*\s*$'
        $found = [regex]::IsMatch($content, $pattern)

        New-CheckResult -Category 'readme-section' -Name $section -Passed $found -Message $(
            if ($found) { "Found heading '$section'." } else { "README is missing a heading '$section'." }
        )
    }
}

function Test-ForbiddenFile {
    <#
    .SYNOPSIS
        Fails when files matching a forbidden glob are committed.

    .DESCRIPTION
        Useful for catching things that should never be in a repository,
        such as *.pfx, *.pem or local settings files.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject[]])]
    param(
        [Parameter(Mandatory)][string]$Path,
        [string[]]$ForbiddenPattern = @()
    )

    $patterns = @(
        $ForbiddenPattern |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
            ForEach-Object { $_.Trim() }
    )
    if ($patterns.Count -eq 0) { return }

    foreach ($pattern in $patterns) {
        $matched = @(
            Get-ChildItem -LiteralPath $Path -Recurse -File -Filter $pattern -ErrorAction SilentlyContinue |
                Where-Object { $_.FullName -notmatch '[\\/]\.git[\\/]' } |
                ForEach-Object { [IO.Path]::GetRelativePath($Path, $_.FullName) -replace '\\', '/' }
        )

        $passed = $matched.Count -eq 0

        New-CheckResult -Category 'forbidden-file' -Name $pattern -Passed $passed -Message $(
            if ($passed) {
                "No files match the forbidden pattern '$pattern'."
            }
            else {
                "Found $($matched.Count) forbidden file(s) matching '$pattern': $($matched -join ', ')."
            }
        )
    }
}

function Invoke-RepoStandardsCheck {
    <#
    .SYNOPSIS
        Runs every configured check and returns a single structured summary.

    .OUTPUTS
        A summary object with Result, Total, Passed, Failed and Checks.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][string]$Path,
        [string[]]$RequiredFile = @(),
        [string[]]$RequiredReadmeSection = @(),
        [string[]]$ForbiddenPattern = @()
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        throw "Path '$Path' does not exist or is not a directory."
    }

    $root = (Resolve-Path -LiteralPath $Path).Path

    $checks = @()
    $checks += Test-RequiredFile    -Path $root -RequiredFile $RequiredFile
    $checks += Test-ReadmeSection   -Path $root -RequiredSection $RequiredReadmeSection
    $checks += Test-ForbiddenFile   -Path $root -ForbiddenPattern $ForbiddenPattern

    $failed = @($checks | Where-Object { -not $_.Passed })

    [pscustomobject]@{
        Result      = if ($failed.Count -eq 0) { 'passed' } else { 'failed' }
        Total       = $checks.Count
        Passed      = $checks.Count - $failed.Count
        Failed      = $failed.Count
        Path        = $root
        GeneratedAt = (Get-Date).ToUniversalTime().ToString('o')
        Checks      = $checks
    }
}

function ConvertTo-MarkdownReport {
    <#
    .SYNOPSIS
        Renders a summary object as Markdown, suitable for a job summary.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory, ValueFromPipeline)][psobject]$Summary,
        [string]$Title = 'Repository standards'
    )

    process {
        $icon = if ($Summary.Result -eq 'passed') { '✅' } else { '❌' }

        $lines = [System.Collections.Generic.List[string]]::new()
        $lines.Add("## $icon $Title")
        $lines.Add('')
        $lines.Add("**$($Summary.Passed)/$($Summary.Total)** checks passed.")
        $lines.Add('')

        if ($Summary.Total -gt 0) {
            $lines.Add('| | Check | Detail |')
            $lines.Add('| --- | --- | --- |')
            foreach ($check in $Summary.Checks) {
                $mark = if ($check.Passed) { '✅' } else { '❌' }
                $lines.Add("| $mark | ``$($check.Category)`` ``$($check.Name)`` | $($check.Message) |")
            }
        }
        else {
            $lines.Add('_No checks were configured._')
        }

        $lines -join "`n"
    }
}

Export-ModuleMember -Function @(
    'Invoke-RepoStandardsCheck'
    'Test-RequiredFile'
    'Test-ReadmeSection'
    'Test-ForbiddenFile'
    'ConvertTo-MarkdownReport'
    'New-CheckResult'
)

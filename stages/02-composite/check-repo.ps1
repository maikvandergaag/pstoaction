#Requires -Version 7.0

[CmdletBinding()]
param(
    [string]$Path = '.',

    [string]$RequiredFiles = 'README.md,LICENSE,.gitignore',

    [string]$RequiredReadmeSections = '',

    [bool]$FailOnError = $true
)

$ErrorActionPreference = 'Stop'

$root = (Resolve-Path -LiteralPath $Path).Path
Write-Host "Checking $root"

$failed = 0
$passed = 0

function Write-Result {
    param([bool]$Ok, [string]$Message)
    if ($Ok) {
        Write-Host "  [PASS] $Message"
        $script:passed++
    }
    else {
        Write-Host "::error ::$Message"
        $script:failed++
    }
}

foreach ($file in ($RequiredFiles -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })) {
    $exists = Test-Path -LiteralPath (Join-Path $root $file)
    Write-Result -Ok $exists -Message "Required file '$file'$(if (-not $exists) { ' is missing' })"
}

$readmePath = Join-Path $root 'README.md'
$sections = $RequiredReadmeSections -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ }

if ($sections -and (Test-Path -LiteralPath $readmePath)) {
    $readme = Get-Content -LiteralPath $readmePath -Raw
    foreach ($section in $sections) {
        $found = $readme -match ('(?m)^#{1,6}\s+' + [regex]::Escape($section) + '\s*$')
        Write-Result -Ok $found -Message "README section '$section'$(if (-not $found) { ' is missing' })"
    }
}

$total = $passed + $failed
$result = if ($failed -eq 0) { 'passed' } else { 'failed' }

Write-Host ""
Write-Host "$passed/$total checks passed."

# Outputs, so a caller can react to the result.
if ($env:GITHUB_OUTPUT) {
    "result=$result"          | Out-File -FilePath $env:GITHUB_OUTPUT -Append
    "checks-total=$total"     | Out-File -FilePath $env:GITHUB_OUTPUT -Append
    "checks-failed=$failed"   | Out-File -FilePath $env:GITHUB_OUTPUT -Append
}

if ($FailOnError -and $failed -gt 0) {
    exit 1
}

exit 0

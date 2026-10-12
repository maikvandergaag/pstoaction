Write-Host "Checking repository standards..." -ForegroundColor Cyan

# Hard-coded. Changing this means editing every copy, everywhere.
$requiredFiles = @("README.md", "LICENSE", ".gitignore")

$problems = 0

foreach ($file in $requiredFiles) {
    if (Test-Path $file) {
        Write-Host "  OK      $file" -ForegroundColor Green
    }
    else {
        Write-Host "  MISSING $file" -ForegroundColor Red
        $problems = $problems + 1
    }
}

# Team Beta added this bit. Team Alpha's copy does not have it.
$readme = Get-Content "README.md" -Raw
if ($readme -notmatch "## Usage") {
    Write-Host "  MISSING README section: ## Usage" -ForegroundColor Red
    $problems = $problems + 1
}

Write-Host ""
Write-Host "Found $problems problem(s)."

# No exit code. The pipeline is green even when the repo is broken.

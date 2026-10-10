#Requires -Version 7.0

<#
    Contract tests for the action entry point.

    These do not test the checking logic again. They test the promises the
    action makes to its consumers: exit codes, outputs and input parsing.
    Those are the things that break people when you change them.
#>

BeforeAll {
    $script:EntryScript = Join-Path $PSScriptRoot '..' 'scripts' 'Invoke-RepoStandardsCheck.ps1'

    function New-TestRepo {
        param([hashtable]$Files = @{})

        $repo = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $repo -Force | Out-Null

        foreach ($name in $Files.Keys) {
            $target = Join-Path $repo $name
            $dir = Split-Path -Parent $target
            if ($dir -and -not (Test-Path $dir)) {
                New-Item -ItemType Directory -Path $dir -Force | Out-Null
            }
            Set-Content -LiteralPath $target -Value $Files[$name]
        }

        $repo
    }

    function Invoke-Entry {
        <#
            Runs the entry script in a child pwsh process so we can observe
            the real exit code, exactly like a workflow runner would.
        #>
        param([hashtable]$Arguments)

        $outputFile = Join-Path $TestDrive "out_$([guid]::NewGuid().ToString('N')).txt"
        New-Item -ItemType File -Path $outputFile -Force | Out-Null

        $argList = @('-NoProfile', '-NonInteractive', '-File', $script:EntryScript)
        foreach ($key in $Arguments.Keys) {
            $argList += "-$key"
            $argList += [string]$Arguments[$key]
        }

        $previous = $env:GITHUB_OUTPUT
        $env:GITHUB_OUTPUT = $outputFile
        try {
            $stdout = & pwsh @argList 2>&1
            $exitCode = $LASTEXITCODE
        }
        finally {
            $env:GITHUB_OUTPUT = $previous
        }

        $outputs = @{}
        foreach ($line in (Get-Content -LiteralPath $outputFile -ErrorAction SilentlyContinue)) {
            if ($line -match '^([a-z0-9-]+)=(.*)$') {
                $outputs[$Matches[1]] = $Matches[2]
            }
        }

        [pscustomobject]@{
            ExitCode = $exitCode
            Stdout   = ($stdout -join "`n")
            Outputs  = $outputs
        }
    }
}

Describe 'Action contract: exit codes' {

    It 'exits 0 when all checks pass' {
        $repo = New-TestRepo @{ 'README.md' = '# Title' }

        $run = Invoke-Entry @{ Path = $repo; RequiredFile = 'README.md' }

        $run.ExitCode | Should -Be 0
    }

    It 'exits 1 when a check fails and fail-on-error is true' {
        $repo = New-TestRepo @{}

        $run = Invoke-Entry @{ Path = $repo; RequiredFile = 'LICENSE' }

        $run.ExitCode | Should -Be 1
    }

    It 'exits 0 when a check fails but fail-on-error is false' {
        $repo = New-TestRepo @{}

        $run = Invoke-Entry @{ Path = $repo; RequiredFile = 'LICENSE'; FailOnError = 'false' }

        $run.ExitCode | Should -Be 0
        $run.Outputs['result'] | Should -Be 'failed'
    }
}

Describe 'Action contract: outputs' {

    It 'sets every documented output' {
        $repo = New-TestRepo @{ 'README.md' = '# Title' }

        $run = Invoke-Entry @{ Path = $repo; RequiredFile = 'README.md' }

        $run.Outputs.Keys | Should -Contain 'result'
        $run.Outputs.Keys | Should -Contain 'checks-total'
        $run.Outputs.Keys | Should -Contain 'checks-passed'
        $run.Outputs.Keys | Should -Contain 'checks-failed'
    }

    It 'reports accurate counts' {
        $repo = New-TestRepo @{ 'README.md' = '# Title' }

        $run = Invoke-Entry @{ Path = $repo; RequiredFile = "README.md`nLICENSE" }

        $run.Outputs['checks-total']  | Should -Be '2'
        $run.Outputs['checks-passed'] | Should -Be '1'
        $run.Outputs['checks-failed'] | Should -Be '1'
        $run.Outputs['result']        | Should -Be 'failed'
    }
}

Describe 'Action contract: input parsing' {

    It 'accepts a newline-separated list' {
        $repo = New-TestRepo @{ 'README.md' = '# Title'; 'LICENSE' = 'MIT' }

        $run = Invoke-Entry @{ Path = $repo; RequiredFile = "README.md`nLICENSE" }

        $run.Outputs['checks-total'] | Should -Be '2'
        $run.ExitCode | Should -Be 0
    }

    It 'accepts a comma-separated list' {
        $repo = New-TestRepo @{ 'README.md' = '# Title'; 'LICENSE' = 'MIT' }

        $run = Invoke-Entry @{ Path = $repo; RequiredFile = 'README.md,LICENSE' }

        $run.Outputs['checks-total'] | Should -Be '2'
    }

    It 'ignores blank lines and comments' {
        $repo = New-TestRepo @{ 'README.md' = '# Title' }

        $run = Invoke-Entry @{ Path = $repo; RequiredFile = "README.md`n`n# a comment`n" }

        $run.Outputs['checks-total'] | Should -Be '1'
    }

    It 'treats an empty input as no checks' {
        $repo = New-TestRepo @{}

        $run = Invoke-Entry @{ Path = $repo; RequiredFile = '' }

        $run.Outputs['checks-total'] | Should -Be '0'
        $run.ExitCode | Should -Be 0
    }
}

Describe 'Action contract: report file' {

    It 'writes valid JSON to the requested path' {
        $repo = New-TestRepo @{ 'README.md' = '# Title' }
        $reportPath = Join-Path $TestDrive 'reports' 'standards.json'

        $run = Invoke-Entry @{ Path = $repo; RequiredFile = 'README.md'; ReportPath = $reportPath }

        Test-Path $reportPath | Should -BeTrue
        $json = Get-Content -LiteralPath $reportPath -Raw | ConvertFrom-Json
        $json.Result | Should -Be 'passed'
        $run.Outputs['report-path'] | Should -Be $reportPath
    }
}

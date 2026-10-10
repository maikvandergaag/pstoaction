#Requires -Version 7.0

BeforeAll {
    $script:ModulePath = Join-Path $PSScriptRoot '..' 'src' 'RepoStandards' 'RepoStandards.psm1'
    Import-Module $script:ModulePath -Force
}

AfterAll {
    Remove-Module RepoStandards -Force -ErrorAction SilentlyContinue
}

Describe 'Test-RequiredFile' {

    BeforeEach {
        $script:repo = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $script:repo -Force | Out-Null
    }

    It 'passes when the file exists' {
        Set-Content -Path (Join-Path $script:repo 'README.md') -Value '# Hi'

        $result = Test-RequiredFile -Path $script:repo -RequiredFile 'README.md'

        $result.Passed | Should -BeTrue
        $result.Category | Should -Be 'required-file'
    }

    It 'fails when the file is missing' {
        $result = Test-RequiredFile -Path $script:repo -RequiredFile 'LICENSE'

        $result.Passed | Should -BeFalse
        $result.Message | Should -BeLike '*LICENSE*missing*'
    }

    It 'returns one result per required file' {
        $result = @(Test-RequiredFile -Path $script:repo -RequiredFile 'a.txt', 'b.txt', 'c.txt')

        $result.Count | Should -Be 3
    }

    It 'supports files in sub directories' {
        New-Item -ItemType Directory -Path (Join-Path $script:repo '.github') -Force | Out-Null
        Set-Content -Path (Join-Path $script:repo '.github' 'CODEOWNERS') -Value '* @team'

        $result = Test-RequiredFile -Path $script:repo -RequiredFile '.github/CODEOWNERS'

        $result.Passed | Should -BeTrue
    }

    It 'does not treat a directory as a file' {
        New-Item -ItemType Directory -Path (Join-Path $script:repo 'docs') -Force | Out-Null

        $result = Test-RequiredFile -Path $script:repo -RequiredFile 'docs'

        $result.Passed | Should -BeFalse
    }

    It 'returns nothing when no files are required' {
        $result = @(Test-RequiredFile -Path $script:repo -RequiredFile @())

        $result.Count | Should -Be 0
    }
}

Describe 'Test-ReadmeSection' {

    BeforeEach {
        $script:repo = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $script:repo -Force | Out-Null
    }

    It 'finds a heading regardless of level' {
        Set-Content -Path (Join-Path $script:repo 'README.md') -Value "# Title`n### Usage`nsome text"

        $result = Test-ReadmeSection -Path $script:repo -RequiredSection 'Usage'

        $result.Passed | Should -BeTrue
    }

    It 'matches case-insensitively' {
        Set-Content -Path (Join-Path $script:repo 'README.md') -Value "## USAGE"

        $result = Test-ReadmeSection -Path $script:repo -RequiredSection 'usage'

        $result.Passed | Should -BeTrue
    }

    It 'does not match the word inside a paragraph' {
        Set-Content -Path (Join-Path $script:repo 'README.md') -Value 'Please read the Usage notes.'

        $result = Test-ReadmeSection -Path $script:repo -RequiredSection 'Usage'

        $result.Passed | Should -BeFalse
    }

    It 'fails gracefully when README.md does not exist' {
        $result = Test-ReadmeSection -Path $script:repo -RequiredSection 'Usage'

        $result.Passed | Should -BeFalse
        $result.Message | Should -BeLike '*does not exist*'
    }

    It 'handles an empty README without throwing' {
        Set-Content -Path (Join-Path $script:repo 'README.md') -Value ''

        { Test-ReadmeSection -Path $script:repo -RequiredSection 'Usage' } | Should -Not -Throw
    }

    It 'returns nothing when no sections are required' {
        $result = @(Test-ReadmeSection -Path $script:repo -RequiredSection @())

        $result.Count | Should -Be 0
    }
}

Describe 'Test-ForbiddenFile' {

    BeforeEach {
        $script:repo = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $script:repo -Force | Out-Null
    }

    It 'passes when nothing matches' {
        Set-Content -Path (Join-Path $script:repo 'README.md') -Value '# Hi'

        $result = Test-ForbiddenFile -Path $script:repo -ForbiddenPattern '*.pfx'

        $result.Passed | Should -BeTrue
    }

    It 'fails when a forbidden file is committed' {
        Set-Content -Path (Join-Path $script:repo 'cert.pfx') -Value 'nope'

        $result = Test-ForbiddenFile -Path $script:repo -ForbiddenPattern '*.pfx'

        $result.Passed | Should -BeFalse
        $result.Message | Should -BeLike '*cert.pfx*'
    }

    It 'searches sub directories' {
        New-Item -ItemType Directory -Path (Join-Path $script:repo 'deep' 'nested') -Force | Out-Null
        Set-Content -Path (Join-Path $script:repo 'deep' 'nested' 'key.pem') -Value 'nope'

        $result = Test-ForbiddenFile -Path $script:repo -ForbiddenPattern '*.pem'

        $result.Passed | Should -BeFalse
        $result.Message | Should -BeLike '*nested/key.pem*'
    }
}

Describe 'Invoke-RepoStandardsCheck' {

    BeforeEach {
        $script:repo = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $script:repo -Force | Out-Null
    }

    It 'reports passed when every check succeeds' {
        Set-Content -Path (Join-Path $script:repo 'README.md') -Value "# Title`n## Usage"
        Set-Content -Path (Join-Path $script:repo 'LICENSE') -Value 'MIT'

        $summary = Invoke-RepoStandardsCheck -Path $script:repo `
            -RequiredFile 'README.md', 'LICENSE' `
            -RequiredReadmeSection 'Usage'

        $summary.Result | Should -Be 'passed'
        $summary.Total  | Should -Be 3
        $summary.Passed | Should -Be 3
        $summary.Failed | Should -Be 0
    }

    It 'reports failed and counts correctly when checks fail' {
        Set-Content -Path (Join-Path $script:repo 'README.md') -Value '# Title'

        $summary = Invoke-RepoStandardsCheck -Path $script:repo `
            -RequiredFile 'README.md', 'LICENSE' `
            -RequiredReadmeSection 'Usage'

        $summary.Result | Should -Be 'failed'
        $summary.Total  | Should -Be 3
        $summary.Passed | Should -Be 1
        $summary.Failed | Should -Be 2
    }

    It 'passes with zero checks when nothing is configured' {
        $summary = Invoke-RepoStandardsCheck -Path $script:repo

        $summary.Result | Should -Be 'passed'
        $summary.Total  | Should -Be 0
    }

    It 'throws a clear error for a path that does not exist' {
        { Invoke-RepoStandardsCheck -Path (Join-Path $TestDrive 'nope') } |
            Should -Throw '*does not exist*'
    }

    It 'produces a summary that survives a JSON round trip' {
        Set-Content -Path (Join-Path $script:repo 'README.md') -Value '# Title'

        $summary = Invoke-RepoStandardsCheck -Path $script:repo -RequiredFile 'README.md'
        $rehydrated = $summary | ConvertTo-Json -Depth 5 | ConvertFrom-Json

        $rehydrated.Result | Should -Be 'passed'
        $rehydrated.Checks.Count | Should -Be 1
    }
}

Describe 'ConvertTo-MarkdownReport' {

    BeforeEach {
        $script:repo = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $script:repo -Force | Out-Null
    }

    It 'renders a success marker and the score' {
        Set-Content -Path (Join-Path $script:repo 'README.md') -Value '# Title'
        $summary = Invoke-RepoStandardsCheck -Path $script:repo -RequiredFile 'README.md'

        $markdown = $summary | ConvertTo-MarkdownReport

        $markdown | Should -BeLike '*✅*'
        $markdown | Should -BeLike '*1/1*'
    }

    It 'renders a failure marker when a check failed' {
        $summary = Invoke-RepoStandardsCheck -Path $script:repo -RequiredFile 'LICENSE'

        $markdown = $summary | ConvertTo-MarkdownReport

        $markdown | Should -BeLike '*❌*'
    }

    It 'explains itself when no checks were configured' {
        $summary = Invoke-RepoStandardsCheck -Path $script:repo

        $markdown = $summary | ConvertTo-MarkdownReport

        $markdown | Should -BeLike '*No checks were configured*'
    }
}

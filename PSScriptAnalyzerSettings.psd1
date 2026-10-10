@{
    # Only genuine errors should break the build. Warnings are surfaced as
    # annotations so they are visible without being a gate.
    Severity = @('Error', 'Warning')

    ExcludeRules = @(
        # Write-Host is the correct choice here: GitHub Actions workflow
        # commands such as ::error:: must go to the host stream.
        'PSAvoidUsingWriteHost',

        # The entry script uses string 'true'/'false' parameters on purpose,
        # because that is what action inputs are.
        'PSAvoidUsingPlainTextForPassword',

        # New-/Set- helpers here are pure factories and local writes inside a
        # single action run. -WhatIf support would be ceremony, not safety.
        'PSUseShouldProcessForStateChangingFunctions',

        # A BOM is only needed for Windows PowerShell 5.1. Everything here is
        # '#Requires -Version 7.0', where UTF-8 without BOM is correct.
        'PSUseBOMForUnicodeEncodedFile'
    )

    Rules = @{
        PSUseCompatibleSyntax = @{
            Enable         = $true
            TargetVersions = @('7.0')
        }
    }
}

# Testing the script, and testing the action

These are two different things, and both are needed.

| | Unit tests | Contract tests | Workflow tests |
| --- | --- | --- | --- |
| **File** | `tests/RepoStandards.Tests.ps1` | `tests/Action.Contract.Tests.ps1` | `.github/workflows/test-action.yml` |
| **Proves** | The logic is correct | Exit codes and outputs behave | `action.yml` is wired correctly |
| **Runs in** | A second, locally | A few seconds, locally | A real runner |

## Why the code is split the way it is

```
src/RepoStandards/RepoStandards.psm1   ← pure logic, no GitHub knowledge
scripts/Invoke-RepoStandardsCheck.ps1  ← inputs, outputs, exit code
action.yml                             ← the contract
```

Stage 2 had all of this in one file, and that file could not be unit tested
without faking environment variables and capturing console output.

Splitting it is not architectural purity. It is the difference between tests
that run in one second and tests that need a workflow run to tell you
anything.

## Running them

```powershell
Invoke-Pester -Path ./tests -Output Detailed
```

## A real bug this caught

While building this demo, every unit test passed but the contract tests
failed with:

```
ForEach-Object: You cannot call a method on a null-valued expression.
```

The cause: in PowerShell, returning `@()` from a function **unrolls to
`$null`**, and piping `$null` executes the loop body once with a null value.

```powershell
function Get-Nothing { return @() }
(Get-Nothing).Count        # 0 — looks fine
Get-Nothing | ForEach-Object { $_.Trim() }   # boom
```

The fix is the leading comma:

```powershell
return , [string[]]$items
```

This is worth demonstrating live. The unit tests passed because they called
the function with a literal `@()`. Only the end-to-end contract test, running
the script the way a runner runs it, exposed it. That is the argument for
having both layers, made concrete.

## What the contract tests actually do

They run the entry script in a **child `pwsh` process**, with
`$env:GITHUB_OUTPUT` pointed at a temp file:

```powershell
$env:GITHUB_OUTPUT = $outputFile
$stdout = & pwsh -NoProfile -File $EntryScript @argList
$exitCode = $LASTEXITCODE
```

That gives you the real exit code and the real outputs — the two things a
workflow depends on and a dot-sourced test can never observe.

## What to test in the workflow

Not the logic again. Test the wiring:

- the happy path produces the outputs you documented
- a failing repository makes the step **fail** (use `continue-on-error: true`
  plus an assertion on `steps.<id>.outcome`)
- `fail-on-error: false` reports without failing
- it works on Linux, Windows and macOS, if you claim it does
- the action passes its own checks (**dogfooding**)

```yaml
- id: check
  continue-on-error: true
  uses: ./
  with:
    path: sample-repos/bad

- run: |
    if ('${{ steps.check.outcome }}' -ne 'failure') {
      throw 'Expected the action to fail.'
    }
  shell: pwsh
```

Testing that something fails correctly is as important as testing that it
passes. Most broken quality gates are broken by being silently green.

## Linting

`PSScriptAnalyzer` runs in CI with `PSScriptAnalyzerSettings.psd1`. Findings
become annotations; only `Error` severity fails the build. Every excluded rule
in that file carries a comment explaining *why* — which is the difference
between a considered exception and silencing the linter.

## The habit to take home

> If a change to the script can break someone else's pipeline, there should
> be a test that fails first.

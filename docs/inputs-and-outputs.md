# Designing inputs and outputs

The moment you publish an action, `action.yml` stops being configuration and
becomes an **API**. Other teams build on it. Changing it carelessly breaks
their pipelines at the worst possible moment.

This is the part of the session worth slowing down for.

## Inputs

### Everything is a string

There are no booleans, numbers or arrays in action inputs. There are strings.

```yaml
fail-on-error:
  default: 'true'     # quoted, because it is text
```

Handle that honestly in the script rather than hoping:

```powershell
[ValidateSet('true','false')]
[string]$FailOnError = 'true'
```

`ValidateSet` turns a typo into an immediate, readable failure instead of
silently treating `yes` as false.

### Prefer lists over separators

A comma-separated input looks fine until a value contains a comma.

```yaml
# Fragile
required-files: README.md,LICENSE

# Better: YAML block scalars give you real multi-line input
required-files: |
  README.md
  LICENSE
  .github/CODEOWNERS
```

Accept both. Splitting on `[\r\n,]+` costs one regex and removes an entire
class of support questions.

### Give every input a default that does something sensible

A consumer should be able to write `uses: your-org/repo-standards-action@v1`
with no `with:` block at all and still get value. Defaults are documentation
that executes.

### Never interpolate input into a shell block

This is the one to say out loud:

```yaml
# Dangerous: the value becomes part of the script
run: ./check.ps1 -Path '${{ inputs.path }}'

# Safe: the value is data, not code
env:
  INPUT_PATH: ${{ inputs.path }}
run: ./check.ps1 -Path $env:INPUT_PATH
```

With the first form, an input containing a quote changes what runs. With the
second it cannot. This repository uses the second form throughout.

### Naming

Use `kebab-case`, because that is the convention in the ecosystem. Name for
intent, not implementation: `fail-on-error`, not `exit-code-mode`.

## Outputs

### Fail loudly, but also report

An action that only fails is a dead end. An action that reports lets people
build things: dashboards, PR comments, gradual rollouts.

| Output | Why it exists |
| --- | --- |
| `result` | One word to branch on. |
| `checks-total` / `checks-passed` / `checks-failed` | Trend-able numbers. |
| `report-json` | The full detail, for anything you did not anticipate. |
| `report-path` | A file, for uploading as an artifact. |

### Always set every output

Even on failure. A consumer writing
`if: steps.x.outputs.result == 'failed'` needs the output to exist when things
went wrong — which is exactly when a naive implementation skips setting it.

### Multi-line outputs need a delimiter

```powershell
$delimiter = "ghadelim_$([guid]::NewGuid().ToString('N'))"
Add-Content $env:GITHUB_OUTPUT "report-json<<$delimiter"
Add-Content $env:GITHUB_OUTPUT $json
Add-Content $env:GITHUB_OUTPUT $delimiter
```

`name=value` silently truncates at the first newline. The random delimiter
also means a value containing the delimiter cannot forge an output.

## Three more things consumers notice

**Annotations.** `::error title=...::message` puts the problem on the
pull request diff, not in log line 4,312.

**Job summaries.** Writing Markdown to `$GITHUB_STEP_SUMMARY` turns a run
into a report someone will actually read.

**Exit codes.** `exit 1` is the difference between a check and a decoration.

## The rule of thumb

> Inputs are a promise you make. Outputs are a promise other people depend on.
> Both are easier to add than to change.

Start smaller than feels comfortable. You can always add an input in a minor
version. Removing one needs a major.

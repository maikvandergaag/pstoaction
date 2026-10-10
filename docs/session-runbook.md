# Session runbook

A timed walkthrough for presenting this repository. Scaled for **45 minutes**;
cut marks are noted for a 30-minute slot.

## Before you start

```powershell
# 1. Confirm everything is green
Invoke-Pester -Path ./tests -Output Detailed      # expect 33 passed

# 2. Have these open in tabs
#    - stages/01-script/check-repo.ps1
#    - stages/02-composite/action.yml
#    - action.yml
#    - tests/Action.Contract.Tests.ps1
#    - a finished Actions run showing the job summary

# 3. Push a tag beforehand so you have a real release to point at
git tag v1.0.0 && git push origin v1.0.0
```

Pre-record or pre-run the workflow screenshots. Live Actions runs take 40
seconds and kill the pacing.

---

## 0:00 — The problem (4 min)

Ask the room: *"Who has more than one copy of the same deployment script in
your organisation?"* Most hands go up.

Open `stages/01-script/check-repo.ps1`. Read it out loud. It is twenty lines
and everyone recognises it.

Then land the point:

> This script is fine. The way we **share** it is the problem.

Walk the table in `stages/01-script/README.md`: no inputs, no outputs, no exit
code, no version, no tests. Distribution is copy/paste, so drift is not a
risk — it is a guarantee.

---

## 0:04 — Run it (3 min)

```powershell
cd sample-repos/bad
pwsh ../../stages/01-script/check-repo.ps1
echo $LASTEXITCODE     # 0 — even though checks failed
```

That `0` is the moment. The repository fails every rule and the pipeline is
green.

---

## 0:07 — Stage 2: give it a contract (8 min)

Open `stages/02-composite/action.yml` next to the script.

Three things changed:

1. **Parameters** — the list of required files is an input now, so Team Beta
   does not need their own copy.
2. **Exit code** — `exit 1`. The build fails.
3. **`action.yml`** — a contract you can read without reading PowerShell.

Show the mechanic people get wrong:

```yaml
run: ${{ github.action_path }}/check-repo.ps1
```

> A composite action runs in the **caller's** workspace. `github.action_path`
> is how a step finds files that ship with the action. Forget it and your
> action works for you and fails for everyone else.

**Cut for 30 min:** skip the backtick-continuation gotcha.

Then ask what is still wrong, and let the room answer. They will say "tests".

---

## 0:15 — Designing inputs and outputs (10 min)

📄 `docs/inputs-and-outputs.md`

Three points, in this order:

**1. Everything is a string.** Show `'true'` quoted in `action.yml`, and
`[ValidateSet('true','false')]` in the script. A typo becomes a clear error
instead of silently meaning false.

**2. Never interpolate input into a shell block.** This is the slide people
photograph.

```yaml
# Dangerous — the value becomes part of the script
run: ./check.ps1 -Path '${{ inputs.path }}'

# Safe — the value is data
env:
  INPUT_PATH: ${{ inputs.path }}
run: ./check.ps1 -Path $env:INPUT_PATH
```

**3. Output more than pass/fail.** Show the job summary, then show
`examples/consumer-workflow.yml` turning `report-json` into a PR comment.

> An action that only fails is a dead end. An action that reports lets
> people build things.

---

## 0:25 — Testing (10 min)

📄 `docs/testing.md`

Start with the structure, because it explains itself:

```
src/RepoStandards/   pure logic, knows nothing about GitHub
scripts/             inputs, outputs, exit code
action.yml           the contract
```

Run the suite live — it takes four seconds:

```powershell
Invoke-Pester -Path ./tests -Output Detailed
```

**Then tell the bug story.** This genuinely happened while building this repo:
every unit test passed, and the contract tests failed with
`You cannot call a method on a null-valued expression`.

```powershell
function Get-Nothing { return @() }
(Get-Nothing).Count                          # 0 — looks fine
Get-Nothing | ForEach-Object { $_.Trim() }   # boom
```

Returning `@()` unrolls to `$null`, and piping `$null` runs the body once
with a null. The fix is a leading comma: `return , [string[]]$items`.

> The unit tests passed because they passed a literal `@()`. Only running the
> script the way a runner runs it found this. That is why you need both
> layers.

Then show the contract test asserting that failure works:

```yaml
- id: check
  continue-on-error: true
  uses: ./
```

> Testing that something fails correctly matters as much as testing that it
> passes. Most broken quality gates are broken by being silently green.

**Cut for 30 min:** show the bug story, skip the cross-platform matrix.

---

## 0:35 — Versioning (8 min)

📄 `docs/versioning.md`

Draw the moving tag:

```
v1.0.0 ──┐
v1.1.0 ──┤
v1.2.0 ──┴──◄── v1
```

`v1.2.0` never moves. `v1` is force-pushed on every compatible release.

Show `release.yml` — and point out that tests run **before** the tag moves.

> Moving `v1` onto untested code ships a bug instantly to everyone who took
> your advice to use `@v1`.

Then the question that actually matters. Put the table up and ask the room to
vote on this row:

| Change | Breaking? |
| --- | :---: |
| Make an existing check stricter by default | **Yes** |

Most people say no. Let the discussion happen, then:

> Nothing in the caller changed, and their pipeline went red. That is the
> definition of breaking.

Close with the deprecation path: add behind a new input → warn in logs →
flip the default in `v2` → keep patching `v1`, with a date.

---

## 0:43 — Close (2 min)

Back to the opening question.

> You started with a script in a repository. You now have something with a
> name, a version, a contract and tests. A team can write one line and trust
> it:

```yaml
- uses: your-org/repo-standards-action@v1
```

> And when you need to change it, you can — without breaking everyone.

Point at the repository URL. Everything demonstrated is in it and runs.

---

## If something goes wrong

| Problem | Fallback |
| --- | --- |
| No network | Everything except the workflows runs locally. Use screenshots for Actions runs. |
| Pester missing | `Install-Module Pester -Force -Scope CurrentUser` |
| Wrong PowerShell | Needs 7+. `pwsh -v` before you start. |
| Running behind | Drop the cross-platform matrix and the reusable-workflow example. Never drop the bug story or the versioning table. |

## Questions you will get

**"Why not a Docker action or a JavaScript action?"**
Composite keeps the PowerShell visible, which is the point of the session.
Docker actions are slower to start; JavaScript actions mean rewriting the
script. Composite is the honest path from an existing script.

**"Can we use this with self-hosted runners?"**
Yes — the only requirement is `pwsh` on the runner.

**"How do we stop teams pinning `@main`?"**
Organisation rulesets can restrict which actions are allowed, and Dependabot
keeps SHA pins fresh. Mostly, though: publish a `v1` that does not break, and
people will use it.

**"What about Azure DevOps?"**
Same shape — the task contract differs, the design principles do not.

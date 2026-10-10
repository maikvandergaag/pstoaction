# Workflows in this repository

Four workflows, each making a different point in the session.

| Workflow | Trigger | What it demonstrates |
| --- | --- | --- |
| [`ci.yml`](ci.yml) | push, PR | The logic is tested on Linux, Windows and macOS, linted, and the action is run against this repository. Stage 1 had none of this. |
| [`test-action.yml`](test-action.yml) | push, PR | The **action** is tested, not just the script: outputs arrive, failure actually fails, report-only mode stays green, and awkward input is treated as data. |
| [`release.yml`](release.yml) | tag `v*.*.*` | Tests run **before** `v1` and `v1.2` are repointed, so `@v1` never lands on untested code. |
| [`demo-stages.yml`](demo-stages.yml) | manual | Runs all three stages against the same sample repository and prints the comparison in the job summary. |

## Demoing the stages

```
Actions ▸ Demo — the three stages ▸ Run workflow ▸ repository: bad
```

Four jobs run: Stage 1, Stage 2, Stage 3 and a `compare` job that writes the
summary table. The moment worth pausing on:

> **Stage 1 is green. Stage 3 is red. They looked at the same repository.**

Run it again with `repository: good` to show all three passing, which makes
the point that Stage 1 is not *wrong* — it is just unable to tell you.

No runner, or no network? The same demo runs locally:

```powershell
./scripts/Invoke-StageDemo.ps1            # the bad repo
./scripts/Invoke-StageDemo.ps1 -Sample good
./scripts/Invoke-StageDemo.ps1 -Stage 3   # one stage at a time
```

## Presenting tips

- Run `demo-stages.yml` on `bad` **before** the session. A finished run shows
  instantly; a live one costs you 40 seconds of silence.
- Open a failed `test-action.yml` run to show that a quality gate is only
  trustworthy if you have tested that it fails.
- `ci.yml` has a `dogfood` job: the action checks this repository using the
  same contract a consuming team would write.

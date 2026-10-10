# Versioning

Versioning is what turns "a script we share" into "something teams can
depend on". It is the answer to *"which version is the right one?"* —
the question stage 1 could not answer.

## The three kinds of ref

```yaml
uses: your-org/repo-standards-action@v1        # moving  — recommended
uses: your-org/repo-standards-action@v1.2      # moving  — latest patch
uses: your-org/repo-standards-action@v1.2.0    # fixed   — never changes
uses: your-org/repo-standards-action@a1b2c3d   # fixed   — a commit SHA
uses: your-org/repo-standards-action@main      # ⚠️ not a version at all
```

`v1.2.0` is created once and never moved. `v1` and `v1.2` are **deliberately
mutable pointers** that `release.yml` force-pushes on every release.

That is unusual in Git terms and worth saying explicitly: moving tags are a
convention in the Actions ecosystem, not an accident.

```
v1.0.0 ──┐
v1.1.0 ──┤
v1.2.0 ──┴──◄── v1  (moves here on each compatible release)
```

## What counts as breaking

This is the decision you will make most often.

| Change | Version | Why |
| --- | --- | --- |
| Add a new optional input with a default | **minor** | Existing callers are unaffected. |
| Add a new output | **minor** | Nobody was reading it yet. |
| Fix a check that was wrong | **patch** | Unless it now fails repos that used to pass. |
| Make a check stricter by default | **major** | Green pipelines turn red. Nothing in the caller changed. |
| Rename an input | **major** | Even with a deprecation shim, eventually. |
| Remove an output | **major** | Someone's `if:` silently becomes false. |
| Change the default of `fail-on-error` | **major** | Behaviour changes without the caller asking. |

The trap is the fourth row. Tightening a rule feels like a bug fix to you and
looks like an outage to twelve other teams. **If the same input produces a
different result, it is breaking.**

## Releasing

```bash
git tag v1.2.0
git push origin v1.2.0
```

`release.yml` then:

1. runs the full test suite against that tag,
2. smoke tests the action,
3. force-moves `v1` and `v1.2`,
4. creates a GitHub release with generated notes.

Step 1 matters. Moving `v1` onto untested code instantly ships a bug to
everyone who followed your advice to use `@v1`.

## Shipping a breaking change without an outage

1. **Add, do not change.** Introduce the new behaviour behind a new input,
   defaulted to the old behaviour. Release as a minor.
2. **Warn.** Emit `::warning::` when someone relies on the old path. People
   discover deprecations in logs, not in release notes.
3. **Flip the default in `v2`.** Keep `v1` alive and keep patching it.
4. **Give a date.** "v1 gets security fixes until June" is a plan.
   "v1 is deprecated" is a rumour.

```powershell
if ($LegacyMode -eq 'true') {
    Write-Host "::warning title=Deprecated::legacy-mode is removed in v2. See MIGRATION.md"
}
```

## Pinning: what to tell your consumers

| Context | Recommend |
| --- | --- |
| Internal repositories, trusted action | `@v1` — they get fixes automatically |
| Anything handling secrets or deployments | `@<full SHA>` — an immutable supply chain |
| Third-party actions you do not control | `@<full SHA>`, always |

Dependabot updates SHA pins for you, so the common objection ("pinning means
we never get updates") is solvable.

## Do not break `v1` to teach a lesson

The temptation, once teams depend on you, is to force migration by letting
`v1` rot. Resist it. The entire value of the action is that people trust the
ref they wrote down. The first time `@v1` breaks their pipeline without
warning, they go back to copying the script — and you are back to stage 1.

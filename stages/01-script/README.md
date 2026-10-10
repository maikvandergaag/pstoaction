# Stage 1 — A script in a repository

This is where almost every internal tool starts: a single `.ps1` file that
does something useful.

```powershell
pwsh ./stages/01-script/check-repo.ps1
```

Run it from the root of a repository and it tells you whether the basics are
in place.

## Why teams love it

- It works.
- It took twenty minutes to write.
- You can read the whole thing in one screen.

## Why it hurts six months later

| Problem | What it looks like in practice |
| --- | --- |
| **No inputs** | The list of required files is hard-coded. Team Beta needs `SECURITY.md`, so they edit their copy. |
| **No outputs** | The result only exists as coloured text in a console. Nothing downstream can react to it. |
| **No exit code** | The script always ends successfully. A pipeline calling it is green even when the repo fails every check. |
| **No contract** | `$readme` is read with no check that `README.md` exists. On a fresh repo it throws. |
| **No tests** | Any change is verified by running it once and squinting at the output. |
| **No version** | "Which copy is the right one?" has no answer. There is no `v1`. |
| **Distribution is copy/paste** | The only way to share it is to send the file. Every copy immediately starts drifting. |

## The drift, made visible

Try this: search an organisation for `check-repo.ps1`. You will find several
copies. They will not be identical. Nobody will be able to tell you which one
is correct, because *correct* was never defined anywhere.

That is the real problem. Not the script — the **distribution model**.

## What we want instead

Something a team can reference by name and version:

```yaml
- uses: your-org/repo-standards-action@v1
```

Getting there is the rest of the session.

➡️ Continue to [Stage 2 — a composite action](../02-composite/README.md)

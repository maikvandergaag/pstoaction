# Stage 2 — The same script, now a composite action

We did not rewrite anything. We put a contract around the script.

```yaml
- uses: your-org/repo-standards-action/stages/02-composite@main
  with:
    required-files: README.md,LICENSE,.gitignore,SECURITY.md
    required-readme-sections: Usage,Contributing
```

## What changed

**The script got parameters.** `$RequiredFiles` is no longer hard-coded, so
Team Beta does not need their own copy any more — they pass different values.

**The script got an exit code.** `exit 1` when checks fail. The workflow now
actually fails.

**The script got outputs.** `result`, `checks-total` and `checks-failed` are
written to `$env:GITHUB_OUTPUT`, so later steps can branch on the result.

**`action.yml` is the contract.** Inputs have descriptions and defaults.
Someone can understand how to use this without reading the PowerShell.

## The key mechanic: `github.action_path`

```yaml
run: ${{ github.action_path }}/check-repo.ps1
shell: pwsh
```

A composite action runs in the *caller's* workspace, not its own folder.
`github.action_path` is how the step finds files that ship with the action.
Forgetting it is the single most common reason a composite action works
locally and fails when someone else uses it.

## Gotchas worth showing live

**Everything arrives as a string.** `inputs.fail-on-error` is the text
`'true'`, not a boolean. The `$${{ ... }}` in the `run:` block is a small
trick that renders `$true` for PowerShell. It also happily renders `$banana`
if someone passes nonsense. Stage 3 validates instead.

**Backticks are line continuations** in the `run:` block. One stray space
after a backtick and the arguments silently stop being passed.

**`@main` is not a version.** Every consumer is pinned to whatever you pushed
five minutes ago.

## What is still wrong

| Problem | Why it bites |
| --- | --- |
| **Still no tests** | The only way to know the script works is to push and watch a workflow. |
| **One file does everything** | Checking, formatting and talking to GitHub are tangled together, so none of it can be unit tested in isolation. |
| **Comma-separated inputs** | Breaks the moment a value contains a comma. YAML has multi-line strings; use them. |
| **No structured output** | `checks-failed=3` does not tell you *which* three. |
| **No job summary** | The result is buried in log output. |
| **No version strategy** | Consumers use `@main`. Your next commit is everyone's next commit. |

➡️ Continue to [Stage 3 — the shared action](../../README.md#stage-3--the-shared-action)

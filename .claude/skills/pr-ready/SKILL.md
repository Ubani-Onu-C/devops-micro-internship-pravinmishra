---
name: pr-ready
description: Review the currently staged git diff (git diff --cached) and produce a PR-readiness report plus a drafted Pull Request title and description. Read-only — never writes files or runs state-changing git commands.
allowed-tools: Bash, Read, Grep
disable-model-invocation: true
---

# pr-ready

Inspect **only what is currently staged** (`git diff --cached`) and return two artifacts:

1. A **PR-readiness report** flagging anything concerning in the staged changes.
2. A **drafted Pull Request title and description** based on what is actually staged.

## Hard constraints

This skill is strictly **read-only**. You must NOT, under any circumstances:

- Create, modify, or delete any file (no `Write`, no `Edit`, no shell redirection like `>`, `>>`, `tee`, `sed -i`, `git add`, `git restore`, `rm`, `mv`, `cp`, etc.).
- Run any state-changing git command: no `git commit`, `git push`, `git add`, `git reset`, `git checkout`, `git restore`, `git stash`, `git merge`, `git rebase`, `git tag`, or anything that alters the repo, index, or refs.

Only ever use **read-only inspection commands**. If the analysis seems to call for a mutating action, do not perform it — just describe it in the report and let the user decide.

## Procedure

### 1. Gather the staged changes

Run these read-only commands (in order):

```bash
git diff --cached --stat        # summary of what files are staged
git diff --cached               # the full staged diff
```

If `git diff --cached` produces no output, stop and tell the user there is nothing staged — there is no PR to draft. Do not analyze unstaged or committed changes.

Optionally, for context only (all read-only):

```bash
git status --short              # see staged vs unstaged at a glance
git branch --show-current       # current branch name (useful for the PR)
git log --oneline -5            # recent history for tone/context
```

### 2. Produce the PR-readiness report

Analyze the staged diff and flag concerns. Use `Grep` / `Read` on the diff content or specific staged files as needed to confirm findings. Check for at least:

- **Secrets & credentials** — API keys, tokens, passwords, private keys, connection strings, `.env` values, cloud credentials, anything that looks sensitive.
- **Debug / leftover statements** — `print(`, `console.log(`, `debugger`, `TODO`/`FIXME`/`XXX`, commented-out code, temporary logging, `pdb.set_trace()`, `binding.pry`, etc.
- **Mixed / unrelated changes** — the diff touching multiple unrelated concerns that should be separate PRs (e.g. a feature change bundled with unrelated refactors or config edits).
- **Unclear intent** — changes whose purpose isn't self-evident, large deletions, magic numbers, or anything a reviewer would question.
- **Other risks** — large binary files, generated artifacts, lockfile churn, overly broad changes, missing tests for new logic.

Report format:

- Start with an overall verdict: **Ready**, **Ready with notes**, or **Not ready**.
- List each finding with: severity (🔴 blocker / 🟡 caution / 🟢 note), file:line where possible, and a one-line explanation.
- If nothing concerning is found, say so explicitly.

### 3. Draft the Pull Request

Based strictly on what is actually staged (do not invent changes that aren't in the diff):

- **Title** — concise, imperative mood, ≤ ~70 chars (e.g. `Add pre-commit hook to block risky staged files`).
- **Description** — markdown with:
  - **Summary** — 1–3 sentences on what this change does and why.
  - **Changes** — bullet list of the concrete changes, grouped by file/area.
  - **Notes for reviewers** — anything from the readiness report worth calling out, or "None".

Present the drafted title and description in a copy-pasteable code block so the user can drop it straight into their PR. Do not open, push, or create the PR — drafting only.

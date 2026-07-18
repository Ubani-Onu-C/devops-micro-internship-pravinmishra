---
name: linux-triage
description: Run the read-only Linux/Nginx health-triage script and interpret its output. Invoke explicitly with /linux-triage. Observes and diagnoses only — never modifies system state.
allowed-tools: Bash, Read, Grep
disable-model-invocation: true
---

# Linux/Nginx Health Triage

Run the project's read-only triage script, then interpret its evidence and help the
human operator understand the health of the Ubuntu/Nginx host.

## How to run

1. Execute the triage script and capture its full output:

   ```bash
   bash scripts/linux-triage.sh
   ```

   (If the working directory is not the project root, use the absolute path
   `/home/ubuntu/linux-triage-project/scripts/linux-triage.sh`.)

2. Note the exit code and the per-check results. Exit code meaning:
   - `0` = HEALTHY
   - `1` = WARN
   - `2` = FAIL

3. If you need more context on a WARN/FAIL check, use **read-only** tools only:
   - `Read` to view config files (e.g. `/etc/nginx/nginx.conf`, site configs).
   - `Grep` to search config or logs for relevant patterns.
   - `Bash` for **read-only** inspection commands (e.g. `systemctl status nginx`,
     `ss -tlnp`, `df -hP`, `free -m`, `tail`-ing a log). Never run a command that
     changes state.

## Safety Rules (from CLAUDE.md — non-negotiable)

- You must **NEVER** execute any command that changes system state:
  - No restarting services.
  - No modifying files.
  - No deleting anything.
- You may **only read, analyze, and suggest**.
- Any recovery action must be **manually approved and executed by the human operator**.
- This skill is granted only the `Bash`, `Read`, and `Grep` tools — it has no
  `Write` or `Edit` capability by design. Do not attempt to work around this.

## Output Rules (from CLAUDE.md — non-negotiable)

- Base **all diagnoses strictly on the evidence** returned by the triage script
  (and any read-only follow-up inspection).
- Do **not invent or assume** information that is not present in the output.
- When you propose a recovery command, you must **clearly label it as a SUGGESTION
  that requires human execution** — never present it as something you will run or
  have run. For example:

  > **Suggested recovery (for human execution only):** `sudo systemctl restart nginx`
  > — please review and run this yourself; I will not execute it.

## Interpreting results

For each check, summarize:
- **What the evidence shows** (quote the relevant line from the script output).
- **What it likely means** (grounded only in that evidence).
- **A suggested next step**, clearly labeled as a human-executed suggestion when it
  involves any state change.

Close with the **overall status** (HEALTHY / WARN / FAIL) and the exit code, and
remind the operator that all recovery actions are theirs to approve and execute.

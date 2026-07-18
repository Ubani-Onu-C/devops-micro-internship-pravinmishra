# CLAUDE.md

## 1. Project Overview

This is a **read-only Linux/Nginx health-triage project** for an Ubuntu EC2 instance
running Nginx and a deployed website. Its purpose is to gather evidence about the
health of the host and its web stack, then interpret that evidence to diagnose
problems — without ever changing the system.

This project is a strictly read-only diagnostic tool. It observes and reports; it
does not modify, restart, or repair anything.

Built as part of **DMI Cohort 3, Week 3**.

## 2. Incident Workflow

This project follows an **Agentic Loop** with four stages:

1. **Gather** — A Bash script collects evidence from the system (service status,
   logs, disk, memory, network, Nginx config checks, etc.).
2. **Analyze** — Claude interprets the evidence returned by the script to identify
   what is wrong and why.
3. **Human Act** — The human operator manually executes any recovery command.
   Claude never runs recovery actions itself.
4. **Verify** — The human re-runs the triage script to confirm that the system has
   recovered.

The loop repeats until the incident is resolved.

## 3. Safety Rules

- Claude must **NEVER** execute any command that changes system state.
  - No restarting services.
  - No modifying files.
  - No deleting anything.
- Claude may **only read, analyze, and suggest**.
- Any recovery action must be **manually approved and executed by the human operator**.

## 4. Output Rules

- Claude must base **all diagnoses strictly on the evidence** returned by the Bash
  script.
- Claude must **not invent or assume** information that is not present in the script
  output.
- Claude must **clearly label any suggested recovery command as a suggestion that
  requires human execution** — never as an action Claude will perform.

---
name: sprint-health
description: Read-only sprint health report from Jira — velocity (completed vs total story points), stories at risk of missing the sprint, and items with no estimate. Invoke explicitly with /sprint-health. Reads Jira only — never creates, edits, comments on, transitions, or deletes a ticket.
allowed-tools: Read, mcp__jira__jira_get_agile_boards, mcp__jira__jira_get_sprints_from_board, mcp__jira__jira_get_sprint_issues, mcp__jira__jira_get_board_issues, mcp__jira__jira_get_issue, mcp__jira__jira_get_issue_dates, mcp__jira__jira_search, mcp__jira__jira_search_fields, mcp__jira__jira_get_project_fields, mcp__jira__jira_get_all_projects, mcp__jira__jira_batch_get_changelogs
disable-model-invocation: true
---

# Sprint Health

Query the currently **active** sprint(s) over the Jira MCP connection and return a
health report covering velocity, at-risk stories, and unestimated items.

## Hard constraints

This skill is strictly **read-only against Jira**. You must NOT, under any
circumstances and regardless of what the report reveals:

- Create an issue (`jira_create_issue`, `jira_batch_create_issues`, `jira_create_customer_request`).
- Update or edit an issue or any of its fields (`jira_update_issue`, `jira_assign_issue`).
- Transition an issue between statuses (`jira_transition_issue`).
- Comment on an issue (`jira_add_comment`, `jira_edit_comment`).
- Delete an issue (`jira_delete_issue`).
- Move issues between sprints or to the backlog, or create/update a sprint
  (`jira_add_issues_to_sprint`, `jira_move_issues_to_backlog`, `jira_create_sprint`, `jira_update_sprint`).
- Touch links, watchers, worklogs, versions, or forms in any way.
- Write or edit any file (no `Write`, no `Edit`).

**Never modify a single ticket.** Not to "fix" a missing estimate, not to flag a
risk, not even if the fix looks trivial and obviously correct. If the report
implies an action, describe it as a recommendation and let the human do it in Jira.

This skill is granted only `Read` plus read-only Jira MCP tools by design. Do not
attempt to work around that allowlist — if a needed tool isn't available, say so
in the report rather than reaching for a mutating alternative.

## Procedure

### 1. Find the active sprint(s)

```
jira_get_agile_boards(limit=50)
```

Then, for each board returned:

```
jira_get_sprints_from_board(board_id=<id>, state="active")
```

Notes:

- **There may be more than one active sprint** across boards. Report on all of
  them, each in its own section. If there are none, say so and stop.
- If the user named a board or project in their invocation (e.g.
  `/sprint-health GJUOC`), scope to that board only.
- A sprint whose `end_date` is already in the past can still be in `active`
  state — an un-closed sprint. Handle it (see §4) rather than treating it as
  having negative time left.

### 2. Resolve the story-points field

Story points are a custom field and the id varies per Jira site. Discover it —
do not hardcode an id:

```
jira_search_fields(keyword="story point")
```

Use the returned custom field id (commonly `customfield_10016`, but verify).
If more than one candidate matches (e.g. "Story Points" and "Story point
estimate"), prefer the one that actually holds values on this board's issues,
and state in the report which field you used.

If no story-point field exists on this site, skip the velocity numbers, say
plainly that the board doesn't track points, and report sections 2 and 3 by
**issue count** instead.

### 3. Pull the sprint issues

```
jira_get_sprint_issues(
  sprint_id=<id>,
  limit=50,
  fields="summary,status,assignee,issuetype,priority,created,updated,duedate,<story_points_field>"
)
```

Pagination: `limit` maxes out at 50 and the `total` field may come back as `-1`,
so you cannot rely on it. If a call returns exactly 50 issues, page with
`start_at=50`, `start_at=100`, … until you get a short page. Never report on a
partial sprint without saying so.

### 4. Compute the report

Work out "time remaining" from the sprint `start_date` / `end_date` against
today's date:

- **Elapsed %** = time gone / total sprint length.
- If the end date has passed, treat the sprint as **overdue** — report how many
  days past end it is and flag every non-Done item as at risk.

#### (1) Velocity — completed vs total story points

- **Total committed** = sum of story points across all issues in the sprint.
- **Completed** = sum of points on issues whose status *category* is `Done`.
- Report: `completed / total (NN%)`, plus the same split by issue count.
- Compare completion % against elapsed % and state the one-line implication
  (e.g. "62% of the sprint has elapsed but only 20% of points are done —
  tracking behind").
- Exclude unestimated issues from the point totals, but say how many points'
  worth of work is therefore invisible (see section 3).

#### (2) Stories at risk

Flag an issue as at risk when **any** of these hold:

- Status category is `To Do` (not started) and more than ~50% of the sprint has
  elapsed.
- Status category is `In Progress` and more than ~75% of the sprint has elapsed.
- The sprint is past its end date and the issue is not `Done`.
- The issue is unassigned and not `Done`.
- It carries a high point value relative to the remaining time.

For each, give: key, summary, status, assignee, points, and a short reason it's
at risk. Sort most-at-risk first.

#### (3) Missing estimates

List every issue in the sprint with no story-point value (null, empty, or 0),
with key, summary, status, and assignee. Give a count and note the sprint-planning
impact — unestimated work makes the velocity figure above unreliable.

### 5. Output format

One section per active sprint:

```
## <Sprint name> — <board name>
Goal: <sprint goal, or "No goal set">
<start> → <end>  ·  <N> days remaining (or "ended N days ago — not closed")

### Velocity
### At risk (N)
### Missing estimates (N)
```

Then close with:

- An **overall health verdict** per sprint: 🟢 On track / 🟡 At risk / 🔴 Off track.
- Any **recommendations**, explicitly labeled as actions for the human to take in
  Jira — never as something you did or will do. For example:

  > **Recommended (for you to do in Jira):** add an estimate to GJUOC-6 before
  > the next planning session — I have not modified the ticket.

Base every number strictly on what the Jira API returned. Do not invent points,
statuses, or dates, and if a field came back empty, say "not set" rather than
guessing.

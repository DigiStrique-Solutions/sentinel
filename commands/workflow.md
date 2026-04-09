---
name: sentinel-workflow
description: List, inspect, resume, start, or abort Sentinel workflow runs. Use whenever the user asks about workflow status, wants to resume a paused workflow, wants to start a manual-only workflow explicitly, or wants to see what workflows are active or recently completed. Also use when the user says "where am I in the workflow", "what was I doing", "continue the bug fix", or similar phrasings that imply they have an unfinished workflow run.
---

# Workflow Command

Inspect, resume, and manage Sentinel workflow runs. This command is the user-facing side of the workflow system — the `sentinel-workflow-runner` skill is the protocol that writes state; this command reads and manipulates it.

**Usage:**

```
/sentinel-workflow list                   # list active and recent runs
/sentinel-workflow status [run-id]        # show current step and last events
/sentinel-workflow resume [run-id]        # resume a paused run
/sentinel-workflow start <workflow-name>  # explicit kickoff (for manual-only workflows)
/sentinel-workflow abort [run-id]         # mark a run as abandoned
```

If `[run-id]` is omitted for `status`, `resume`, or `abort`, the command operates on the most recently active run.

## Step 1: Parse the subcommand

Extract the subcommand from the user's message. Recognize these variants:

- `list`, `ls`, `status all` → `list`
- `status`, `what's going on`, `where am I`, `current` → `status`
- `resume`, `continue`, `pick up` → `resume`
- `start`, `kickoff`, `begin`, `run` → `start`
- `abort`, `cancel`, `abandon`, `stop` → `abort`

If the user's intent is unclear, ask which subcommand they meant.

## Step 2: Execute the subcommand

### list

Run the state helper:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/workflow-state.sh" list
```

Show the output to the user as-is. If there are active runs, mention that they can use `status <run-id>` to see details or `resume <run-id>` to continue.

### status [run-id]

If no run-id given, find the most recently active run:

```bash
RID=$(bash "${CLAUDE_PLUGIN_ROOT}/scripts/workflow-state.sh" find-active)
```

If the output is empty, tell the user there are no active runs and suggest `/sentinel-workflow list` to see completed ones.

Otherwise, show the status:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/workflow-state.sh" status "$RID"
```

Then interpret the state.md and events.jsonl for the user in 2-3 sentences: which workflow, current step number and name, last significant event, and what the next action should be.

### resume [run-id]

If no run-id given, find the most recently active run via `find-active`. If there are multiple active runs, list them and ask which to resume.

Once you have the run-id:

1. Read `vault/workflows/runs/<run-id>/state.md` completely
2. Read the last 10 events from `vault/workflows/runs/<run-id>/events.jsonl`
3. Load the workflow skill specified in the state.md frontmatter (e.g., `sentinel-workflow-bug-fix`)
4. Tell the user: "Resuming `<workflow>` at step `<N>` (`<step name>`). Last event: `<event>`. Proceeding."
5. Execute the workflow from the current step, using the runner protocol

Respect idempotency: if a step's artifact already exists in `artifacts/step-N-*.md`, skip that step and move to the next. Do not re-run destructive steps.

### start <workflow-name>

Used for workflows with `disable-model-invocation: true` (e.g., `release`, `deploy`) that don't auto-activate from user intent alone. For those, the user has to explicitly ask.

1. Validate the workflow exists: check for `sentinel-workflow-<name>` skill
2. Invoke the workflow skill directly
3. The skill will call `workflow-state.sh start <name>` itself as its first action

If the workflow doesn't exist, list the available workflow skills and ask the user to pick.

### abort [run-id]

If no run-id given, find the most recently active run. Confirm with the user before aborting (this is destructive — the run moves to `abandoned/`).

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/workflow-state.sh" finish "$RID" aborted
```

Report the result.

## Notes

- The state helper script is at `${CLAUDE_PLUGIN_ROOT}/scripts/workflow-state.sh` — always invoke it with that path.
- All workflow state lives in `vault/workflows/runs/` in the project's vault — it's committed to git alongside code, visible to the whole team.
- If the user is looking for a workflow that doesn't exist, point them at `sentinel-workflow-bug-fix` as the canonical example and suggest copying it into `.claude/skills/workflow-<their-name>/SKILL.md` to author their own.

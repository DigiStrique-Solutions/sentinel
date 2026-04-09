---
name: sentinel-workflow-runner
description: Execution protocol that drives any Sentinel workflow skill — creates run directories, checkpoints progress after each step, persists state across sessions, and supports resumption. Use whenever a workflow skill (any skill with workflow=true in its frontmatter) is active, or whenever the user asks to resume, pause, or check the status of a workflow. Activates automatically alongside any workflow skill — you don't invoke it directly, it becomes the protocol you follow while executing the workflow.
origin: sentinel
---

# Workflow Runner

The runner is the protocol that turns a workflow skill (a markdown playbook) into a trackable, resumable, observable execution. You follow this protocol whenever a Sentinel workflow is active.

## What is a workflow skill

A workflow skill is an ordinary Sentinel skill with `workflow: true` in its frontmatter. Its body is a numbered playbook — sections starting with `## N. <Name>` — that describes a multi-step process. Examples: `sentinel-workflow-bug-fix`, `sentinel-workflow-new-feature`, `sentinel-workflow-refactor`.

When a workflow skill activates, the runner protocol takes over execution. The workflow skill describes *what* to do; the runner describes *how* to track it.

## The three workflow primitives

| Primitive | Location | Purpose |
|---|---|---|
| **Run directory** | `vault/workflows/runs/<run-id>/` | Per-invocation state — one per workflow execution |
| **state.md** | `<run-dir>/state.md` | Human-readable current state — current step, status, per-step outputs |
| **events.jsonl** | `<run-dir>/events.jsonl` | Machine-readable append-only event log — every transition |
| **artifacts/** | `<run-dir>/artifacts/` | Idempotency markers — cached step outputs |

## The execution loop

When a workflow skill becomes active, run this protocol:

### 1. Detect or create a run

Check whether a run is already in progress for this workflow:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/workflow-state.sh" find-active <workflow-name>
```

- If an active run exists, **resume it** — load its `state.md`, find the current step, continue from there.
- If no active run exists, **create a new one**:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/workflow-state.sh" start <workflow-name>
```

This creates `vault/workflows/runs/<workflow-name>-<timestamp>/` with empty `state.md`, `events.jsonl`, and `artifacts/`, and emits a `workflow_started` event. The script prints the new run ID to stdout.

### 2. For each `## N. <Name>` heading in the workflow body

Before starting the step:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/workflow-state.sh" step-start <run-id> <step-number> "<step-name>"
```

This writes a `step_started` event to `events.jsonl` and updates `state.md` with `current_step: N`.

Execute the step — read the checkboxes and prose in that section of the workflow skill, do what it says, call whatever sub-skills or tools are needed.

After the step completes:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/workflow-state.sh" step-complete <run-id> <step-number> "<artifact-path>"
```

This writes a `step_completed` event, marks the step as done in `state.md`, and records any artifact path you produced (used as an idempotency marker on resume).

### 3. On step failure

If a step fails (a test fails, a tool errors, a sub-skill returns nothing useful):

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/workflow-state.sh" step-fail <run-id> <step-number> "<reason>"
```

This writes a `step_failed` event. Then decide:
- **Retry** if the workflow body has a "try again" instruction for this failure
- **Branch** if the workflow body has a documented fallback (e.g., "if the fix attempt fails, jump to investigation")
- **Ask the user** if neither applies
- **Abort** if the workflow can't continue

The workflow skill's body is authoritative on what to do; the runner just records the decision.

### 4. At workflow completion

When every step is done (or the workflow is explicitly stopped):

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/workflow-state.sh" finish <run-id> <status>
```

Where `status` is `completed` | `aborted`. This writes a `workflow_finished` event and moves the run directory to `vault/workflows/runs/completed/` or `vault/workflows/runs/abandoned/`.

## Idempotency and resumption

On resume (new session, `/clear`, compaction recovery), the runner does this:

1. Read `state.md` to find the current step and per-step completion markers
2. Read `events.jsonl` to reconstruct the event history
3. For each step already marked completed with an artifact in `artifacts/`, **skip it** — the artifact file is the idempotency marker
4. Pick up from the current step

This means: **every step that writes an artifact is automatically idempotent.** If the session dies mid-step, the next session sees no artifact for that step and runs it again. If the step already wrote its artifact, the next session sees the marker and skips.

**Design rule**: workflow steps should write their outputs to `artifacts/step-N-<name>.md` so they serve as progress markers. Steps that don't produce artifacts will re-run on resume — this is sometimes desired (idempotent reads) and sometimes wrong (destructive writes). When in doubt, write a marker file.

## Composition with other Sentinel primitives

Workflow steps can invoke existing Sentinel primitives:

| Primitive | How |
|---|---|
| **`/sentinel-loop`** | For "repeat until convergence" sub-patterns. Workflow step says "run `/sentinel-loop 'pytest until green'`". |
| **`/sentinel-batch`** | For "fan-out across work items" sub-patterns. Workflow step says "run `/sentinel-batch 'migrate each file in src/api/'`". |
| **Sub-agents** (code-reviewer, architect, etc.) | Delegate expensive/verbose steps. Workflow step says "delegate the review to the `code-reviewer` subagent". |
| **Other workflows** | Workflow steps can invoke other workflow skills. The runner tracks each invocation as a sub-run with its own run-id, linked from the parent's state.md. |
| **Hooks** | Per-workflow hooks defined in the workflow skill's frontmatter fire only during that workflow's active window. |

## Anti-patterns to avoid

- **Skipping checkpoints** — the entire observability and resumption story depends on calling `workflow-state.sh` at every step transition. Do not skip it to "save time."
- **Ignoring the idempotency marker** — if a step's artifact already exists on resume, do not re-run the step. Re-running destructive steps loses work.
- **Infinite retry loops** — a workflow that retries failed steps forever will loop. Use a max retry count (default 3), and after that, escalate to the user.
- **Monolithic steps** — a workflow with one "## 1. Do everything" step is not a workflow, it's a skill. If a step has no natural stopping point, split it.
- **Implicit composition** — if the workflow uses `/sentinel-loop`, write it explicitly in the workflow body. Don't leave it to Claude to figure out.

## Inspection commands

These are provided by the `/sentinel-workflow` command (separate skill):

```
/sentinel-workflow list              # list active and recent runs
/sentinel-workflow status [run-id]   # current step, last event, next action
/sentinel-workflow resume [run-id]   # resume a paused run
/sentinel-workflow start <workflow>  # explicit kickoff (for manual-only workflows)
/sentinel-workflow abort [run-id]    # mark a run as abandoned
```

The runner and the command compose: the runner writes state, the command reads state.

## When the runner does nothing

The runner is a protocol, not a framework. It adds overhead only at step transitions. If the user invokes a workflow skill and runs exactly one step before stopping, the overhead is:
- 1 `start` call (creates the run dir)
- 1 `step-start` call
- 1 `step-complete` call
- 1 `finish` call

Four bash invocations, each ~50ms. If the overhead is ever problematic, something else is wrong.

## Where state lives

| Path | Purpose |
|---|---|
| `vault/workflows/runs/<run-id>/state.md` | Human-readable state |
| `vault/workflows/runs/<run-id>/events.jsonl` | Append-only event log |
| `vault/workflows/runs/<run-id>/artifacts/` | Idempotency markers |
| `vault/workflows/runs/completed/<run-id>/` | Completed runs (archived) |
| `vault/workflows/runs/abandoned/<run-id>/` | Aborted runs (archived) |

All state lives in the project's vault — committed alongside code, visible to the whole team, naturally backed up.

## The one-page rule

This SKILL.md is the entire workflow engine. If you find yourself wanting to extend it with new primitives (parallel steps, conditional branching, variable binding, loop constructs), stop and reconsider. The workflow body is Claude-readable markdown; Claude is the execution engine. Every new primitive in the runner is a new way for the runner to disagree with what Claude read. Keep the runner thin.

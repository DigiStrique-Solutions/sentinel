---
name: sentinel-plan-execute
description: Use to execute an approved implementation plan end-to-end. Reads the plan, decides whether plan-council is needed (via scripts/plan-needs-council.sh and the plan's `Council required` flag), runs council if so, then routes to subagent-driven-development or executing-plans depending on subagent availability. Activates when the user says "execute this plan", "run the plan", "implement the plan", "let's build this", or whenever an approved plan exists at vault/planning/ and code work is about to start.
origin: sentinel
---

# Plan Execute

The "go" button for an approved plan. This skill does not implement code itself — it composes the other Phase 1/2 skills into a single decision flow:

```
plan file → council gate → executor selection → hand off
```

You stay in control of the orchestration; specialized skills do the work.

## When to use

- An approved plan exists at `vault/planning/<topic>-plan.md`
- The user has signaled "go" — wants implementation to start
- You haven't already run this flow for this plan

## When NOT to use

- No plan exists yet → use `sentinel-writing-plans` first
- Plan is being changed (not executed) → don't run this; revise the plan
- The work is a single-file fix → just do it inline; this is overhead

## The flow

### Step 1: Read the plan

Open `vault/planning/<topic>-plan.md`. Sanity-check:

- Does the plan have a header with goal, architecture, tech stack?
- Does it have a file layout section?
- Does each task have file paths, verification commands, and step-level checkboxes?

If any of these are missing, the plan is under-specified for execution. Stop and fix it (likely re-invoke `sentinel-writing-plans`) before continuing.

### Step 2: Council gate

Run the heuristic:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/plan-needs-council.sh" vault/planning/<topic>-plan.md
```

The script reads the plan and returns JSON like:

```json
{
  "plan_path": "...",
  "needed": true,
  "reasons": ["file_count_above_threshold"],
  "file_count": 7,
  "threshold": 5,
  "explicit_flag": "absent"
}
```

**If `needed: true`:**

Tell the user briefly:

> This plan touches 7 files. Running plan-council before execution to catch structural issues — 1-3 rounds of adversarial review, takes a few minutes. (To skip: add `Council required: false` to the plan header.)

Then invoke `sentinel-plan-council`.

After council returns:
- **If APPROVE** → continue to Step 3
- **If REVISE (within 3-round cap)** → council itself produces the revised plan; re-run Step 2 against the revised plan
- **If 3-round cap hit with unresolved REVISE** → council recorded the dissent in `vault/decisions/<topic>-council.md`. Surface it to the user before continuing:

  > Council ran 3 rounds and didn't reach approval. The unresolved items are in vault/decisions/<topic>-council.md. Do you want to proceed anyway, revise the plan manually, or stop?

  Wait for the user. Don't auto-proceed past unresolved BLOCKER items.

**If `needed: false`:**

Continue to Step 3 silently. (Optional: log the bypass reason for telemetry.)

### Step 3: Select the executor

Choose between:

- **`sentinel-subagent-driven-development`** — the preferred path when subagents are available. Fresh subagent per task with two-stage review.
- **`sentinel-executing-plans`** — single-agent linear execution. Use when subagents are unavailable, OR when the plan's tasks are tightly coupled (every task touches a shared interface so fresh-context dispatch buys nothing).

Decision rule:

```
if subagent_dispatch_available AND tasks_mostly_independent:
    use sentinel-subagent-driven-development
else:
    use sentinel-executing-plans
```

How to assess "tasks mostly independent": look at the plan's file layout. If 80%+ of files are touched by exactly one task, tasks are independent. If most files are touched by multiple tasks, they're coupled.

Tell the user which executor you picked and why:

> Using `sentinel-subagent-driven-development` — 7 of 9 files are touched by exactly one task, so tasks dispatch cleanly to fresh subagents.

### Step 4: Hand off

Invoke the chosen executor skill. The executor skill takes over and follows its own protocol from there.

**Do not** continue to "supervise" the executor from this skill. Once handed off, this skill is done. The executor handles task-by-task progress, the verification chain, and the final hand-off to `sentinel-finishing-a-development-branch`.

## What this skill does NOT do

This skill is a router and a gate. It does not:

- Write or edit code
- Run tests directly
- Make architectural decisions (those happen in brainstorm and writing-plans)
- Decide whether the plan is "good" (that's plan-council's job)
- Execute the plan (that's the executor skills' job)

If you find yourself writing code from inside this skill, you've drifted out of orchestration into implementation. Hand off.

## Failure modes

| Symptom | What it means | Response |
|---|---|---|
| Plan-needs-council script errors | Plan file malformed or path wrong | Investigate; do not skip the council gate by failing open |
| Council returns REVISE three times in a row | Plan has a structural issue not fixable by patches | Stop. Send back to brainstorming or writing-plans. |
| Executor reports "missing context" repeatedly | Plan lacks file paths or surrounding-code references | Plan was under-specified; use sentinel-iterative-retrieval pattern in the plan to enumerate required context per task |
| User says "skip council, just execute" but plan touches 12 files | User overriding the heuristic | Honor the override but log it; record `explicit_override` in the decision file |
| Tasks turn out to be coupled mid-execution | Wrong executor chosen | Pause execution, switch to executing-plans, restart from the last committed task |

## Integration

```
sentinel-brainstorm
   ↓ (spec)
sentinel-writing-plans
   ↓ (plan)
sentinel-plan-execute  ←── you are here
   ├── scripts/plan-needs-council.sh (gate)
   ├── sentinel-plan-council (if needed) → vault/decisions/<topic>-council.md
   └── sentinel-subagent-driven-development OR sentinel-executing-plans
                                       ↓
                          sentinel-verification-before-completion (Iron Law throughout)
                                       ↓
                          sentinel-finishing-a-development-branch
```

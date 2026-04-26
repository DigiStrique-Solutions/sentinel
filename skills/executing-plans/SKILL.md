---
name: sentinel-executing-plans
description: Use to execute an existing implementation plan in a single agent (when subagents are unavailable, or when tasks are too tightly coupled to dispatch independently). Walks the plan task-by-task with TodoWrite, runs verification at each step, and stops at blockers rather than guessing. Activates when an approved plan exists and sentinel-subagent-driven-development is not available.
origin: sentinel
---

# Executing Plans

The single-agent path for executing a plan. Use this when subagent dispatch isn't available, or when the plan's tasks are tightly coupled (every task touches the same shared interface) such that fresh-context dispatch would force the executor to rebuild the same context for each task anyway.

## When to use this vs. subagent-driven-development

| Situation | Skill |
|---|---|
| Subagent dispatch is available + tasks mostly independent | sentinel-subagent-driven-development |
| Subagent dispatch unavailable | this skill |
| Tasks tightly coupled (refactor across shared interface) | this skill |
| Plan has <3 tasks | this skill (dispatch overhead not worth it) |

If you can use subagent-driven-development, prefer it — it gives better quality on long plans because context stays clean.

## The process

### Step 1: Load and review

1. Read the plan file end-to-end (don't skim).
2. Walk the file layout section. Note any concerns:
   - Does any file responsibility seem wrong?
   - Are any obvious files missing?
   - Are tasks ordered sensibly (dependencies before dependents)?
3. If concerns exist, raise them before starting. Do not "fix in flight" silently.
4. Mirror the plan's tasks into TodoWrite (one TodoWrite item per Task, not per step).

### Step 2: Execute one task at a time

For each task in order:

1. Mark the task `in_progress` in TodoWrite.
2. Walk each step in the task block, in order, doing exactly what the step says.
3. Run the task's verification command **fresh** (sentinel-verification-before-completion applies — never claim "this works" without re-running).
4. If verification passes, commit per the task's specified message.
5. Mark the task `completed`.
6. Move to the next task.

Do not start the next task before committing the current one. The plan's atomicity is what makes the verification trail meaningful.

### Step 3: Handle the unexpected

The plan was written before execution. Reality will diverge from the plan. Three failure modes and their responses:

| Symptom | Response |
|---|---|
| A step's expected output doesn't match (test fails when it shouldn't, etc.) | Stop. Investigate. Do not "fix forward" by editing the plan inline. Either the plan is wrong or your implementation is wrong — figure out which. |
| A step says to modify lines X-Y but those lines have changed since the plan was written | Stop. Read the surrounding code. The intent of the step usually still applies, but blindly applying line-number diffs against drifted code is how regressions land. |
| You realize a task earlier in the plan was incomplete | Do not retroactively edit the earlier task. File a new task at the end labeled "Cleanup: <thing>". This keeps the commit history matching the plan. |
| A task you haven't started becomes obviously wrong | Stop. Ask the user. Do not silently re-plan in your head and execute a different plan. |

### Step 4: Run the integration check

After all tasks are marked done:

1. Run the full test suite (not just the per-task verifications).
2. Run the linter and type-checker.
3. Read the cumulative diff (`git diff <branch-base>...HEAD`).
4. Look at the diff with two questions:
   - Are there changes in the diff that no task in the plan asked for?
   - Are there obvious quality issues (dead code, leftover prints, TODO comments) you didn't catch in the per-task reviews?
5. Fix any issues found.

### Step 5: Hand off

Invoke sentinel-finishing-a-development-branch.

## Stopping rules

You must stop and ask the user when:

- A step's instruction is genuinely ambiguous (you would have to make an architectural decision)
- Verification fails and the cause isn't obvious within 2-3 attempts
- The plan turns out to depend on a missing tool, missing data, or missing permission
- You discover the plan and the codebase have drifted apart

You may continue without asking when:

- A step's verification passes on the first try
- A test failure has an obvious typo-level cause and you fix it
- You need to reformat per the linter

The dividing line: stop when continuing requires *judgment*. Continue when it requires *competence*.

## Anti-patterns

- **Executing the plan with the wrong scope** — implementing 3 tasks ahead of where you are because they "look easy" and you'll come back to the boring middle one. Order matters; skipping breaks the verification chain.
- **Inline plan edits** — discovering an issue and silently rewriting the task you're on. The plan is a contract. If it's wrong, surface that, don't paper over it.
- **Skipping commits** — running through 3 tasks and committing once. You've now lost the per-task trace; if a regression appears in task 5, you can't bisect to task 2.
- **Skipping verification** — see sentinel-verification-before-completion. The Iron Law applies to every claim of task completion.

## Integration

- **Input:** approved plan at `vault/planning/<feature>-plan.md`
- **Output:** committed implementation, all tasks marked done in TodoWrite
- **Verification dependency:** sentinel-verification-before-completion
- **Next step:** sentinel-finishing-a-development-branch
- **Preferred alternative:** sentinel-subagent-driven-development when subagents are available

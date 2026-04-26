---
name: sentinel-subagent-driven-development
description: Use to execute an existing implementation plan when subagents (the Agent/Task tool) are available. Dispatches one fresh subagent per task with isolated context, then runs spec-compliance and code-quality reviews after each task. Activates when an approved plan exists at vault/planning/ and the user wants to proceed with implementation. Preferred over sentinel-executing-plans whenever subagent dispatch is possible.
origin: sentinel
---

# Subagent-Driven Development

Execute a plan task-by-task by dispatching a **fresh subagent for each task**, then running **two review passes** (spec compliance, then code quality) before moving on. The orchestrator never inherits subagent context; subagents never inherit orchestrator context. Each agent's working set stays small, focused, and clean.

## Why this works (the load-bearing mechanic)

Single-agent execution accumulates context with every task. By task 5, the agent is reasoning over 50k tokens of prior work, half of which is irrelevant. Decisions get worse. Earlier choices become invisible. The agent "forgets things."

Subagent dispatch breaks this. Each task gets a fresh agent with **only the context it needs**: the relevant plan section, the surrounding files, the verification command. The orchestrator stays in pure coordination mode — it never reads code, it dispatches and reviews. This is the mechanism that fixes "Claude Code forgets things across long sessions."

If you skip the freshness — if you reuse an agent across tasks, or if the orchestrator reads the diffs after every task — you've lost the entire benefit. The discipline matters.

## When this applies

- An approved plan exists at `vault/planning/<feature>-plan.md`
- Tasks are mostly independent (each can complete without state from the next)
- Subagent dispatch is available (Task tool, Agent tool, or equivalent)
- You expect ≥3 tasks (below 3, the dispatch overhead isn't worth it)

If tasks are tightly coupled (e.g., a refactor where every task touches shared interfaces), use sentinel-executing-plans instead. If the plan is too small, just execute inline.

## The orchestrator's role

The orchestrator does **only these four things**:

1. Reads the plan once, into TodoWrite
2. Dispatches one subagent per task
3. Dispatches reviewers and relays their findings back to the implementer
4. Marks the task done in TodoWrite when both reviews pass

The orchestrator does NOT:
- Read the diff
- Read the modified files
- Run the verification commands
- Decide whether the implementation is correct

That last bullet is the hard one. The temptation to "just glance at the diff" is exactly what re-pollutes the orchestrator's context. Resist it. The reviewers are there for a reason.

## The per-task loop

```
For each task in plan:
  1. Dispatch IMPLEMENTER subagent
       - Inputs: this task's section verbatim, paths to surrounding files,
                 verification command, "ask if anything is unclear" instruction
       - Subagent implements, runs verification, commits, then self-reviews
  2. If implementer asks clarifying questions:
       - Answer them, then re-dispatch with the same task + the answers
  3. Dispatch SPEC-COMPLIANCE REVIEWER subagent
       - Inputs: the task's spec section, the git diff, "does the diff match the spec?"
       - Output: APPROVED or REVISIONS NEEDED with specific gaps
  4. If revisions needed:
       - Re-dispatch implementer with revisions list, loop back to 3
  5. Dispatch CODE-QUALITY REVIEWER subagent
       - Inputs: the git diff, vault/quality/anti-patterns.md, "any issues?"
       - Output: APPROVED or REVISIONS NEEDED
  6. If revisions needed:
       - Re-dispatch implementer with revisions list, loop back to 5
  7. Mark task done in TodoWrite
  8. Move to next task
```

Each subagent in this loop gets a **fresh context window**. They do not see prior tasks' implementations, prior reviewers' comments, or the orchestrator's history.

## Subagent prompts (templates)

### Implementer prompt skeleton

```
You are implementing one task from a larger plan. The plan is at
{plan_path}. Your task is below.

You have not seen the previous tasks. You do not need to. Each task is
designed to stand alone given the file paths in its spec.

Task:
<paste the task's full markdown block here, including file paths,
 verification command, and all checkbox steps>

Surrounding context (read these files before implementing):
- {file_path_1}
- {file_path_2}

Process:
1. Read the surrounding context files first
2. If anything in the task is ambiguous, ask before implementing
3. Implement the task following its steps in order
4. Run the verification command — copy the output verbatim into your reply
5. Commit with the message specified in the task
6. Self-review: read your own diff. Anything you'd flag if reviewing?
7. Report what you did, what you committed, and any concerns

Do NOT modify files outside the task's scope.
Do NOT skip the verification step.
Do NOT claim completion without running verification (see
sentinel-verification-before-completion).
```

### Spec-compliance reviewer prompt skeleton

```
You are reviewing whether a code change matches its specification. You
have NOT seen the implementation process — only the spec and the diff.

Spec:
<paste the task's full markdown block>

Diff:
<paste git diff>

Your job: does the diff implement what the spec asked for? Specifically:
- Are all the files in the spec's "Files" section actually changed?
- Does each step's intended outcome appear in the diff?
- Are there changes in the diff that the spec did NOT ask for?

Report APPROVED or REVISIONS NEEDED. If revisions, list each specific
gap as a bullet. Do not comment on style — that's a different review.
```

### Code-quality reviewer prompt skeleton

```
You are reviewing code quality. You have NOT seen the spec or the
implementation process — only the diff and the project's quality rules.

Diff:
<paste git diff>

Quality rules to apply:
- vault/quality/anti-patterns.md
- vault/quality/test-standards.md
- vault/quality/gates.md

Your job: are there quality issues that must be fixed before this is
merge-ready? Specifically check:
- Anti-patterns from anti-patterns.md
- Test quality (per test-standards.md)
- Error handling, edge cases, naming
- Quality gates (per gates.md)

Do NOT comment on whether the diff implements the right thing — that's
a different review.

Report APPROVED or REVISIONS NEEDED with specific items.
```

## Verifying subagent reports

The Iron Law of sentinel-verification-before-completion still applies. When the implementer says "task done, tests pass," the orchestrator must verify *independently* before marking the TodoWrite item complete:

1. Run `git diff HEAD~1` and confirm files changed match the task's spec
2. Run the verification command and check exit code
3. Only then mark the task done

The implementer's report is hearsay. The diff and the test output are evidence.

## Final review pass

After the last task is marked done, dispatch one more reviewer agent — the **integration reviewer** — to look at the cumulative diff (`git diff <branch-base>...HEAD`) and check for issues that only appear at the seams between tasks: API mismatches between two new modules, contradictory error handling, dead code from earlier tasks superseded by later ones.

Then hand off to sentinel-finishing-a-development-branch.

## Failure modes

| Symptom | Likely cause | Fix |
|---|---|---|
| Subagent says "I need to know X to proceed" repeatedly | Plan didn't include X; the executor lacks context the planner had | Pause; update the plan; re-dispatch |
| Spec reviewer keeps approving but quality reviewer keeps rejecting | Implementer is meeting the letter of the spec while making bad code | Strengthen the implementer's anti-patterns context |
| Quality reviewer keeps approving but tests fail | Implementer is skipping verification | Re-emphasize verification-before-completion in implementer prompt |
| Two tasks in a row produce conflicting changes to the same file | Tasks aren't actually independent | Stop; re-decompose; this should have caught it before dispatch |

## Integration

- **Input:** approved plan at `vault/planning/<feature>-plan.md`
- **Output:** committed implementation, all tasks marked done in TodoWrite
- **Next step:** sentinel-finishing-a-development-branch
- **Verification dependency:** sentinel-verification-before-completion (Iron Law applies to all completion claims by both subagents and orchestrator)
- **Fallback:** sentinel-executing-plans if subagent dispatch is unavailable

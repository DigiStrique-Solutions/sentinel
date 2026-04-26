---
name: sentinel-dispatching-parallel-agents
description: Use when facing 2+ independent problems (failing tests in unrelated modules, multiple unrelated bugs, multiple subsystems to investigate) that have no shared state and can be worked on concurrently. Dispatches one fresh subagent per problem domain in parallel. Activates when you would otherwise sequentially debug or implement work that has no dependency between items.
origin: sentinel
---

# Dispatching Parallel Agents

When you have N independent problems, sequential investigation wastes wall-clock time. Each investigation can happen in its own subagent, in parallel, with no shared state. The orchestrator just dispatches and integrates the results.

This is different from sentinel-subagent-driven-development (which dispatches subagents *sequentially* per plan task). The pattern here is **fan-out**, not pipelined execution.

## When to use

Required conditions, all of them:

- ≥ 2 independent problems
- No shared state between them (fixing one will not affect the others' analysis)
- Each can be understood from its own scope without the others' context
- The problems would otherwise be addressed serially

Example fits:
- 4 unrelated test files failing for different reasons
- 3 different subsystems each have a separate bug report
- Multiple security findings in unrelated modules

Example **misfits**:
- Several test files failing because of one shared bug (one investigation, not many)
- Multiple aspects of one feature (use sentinel-subagent-driven-development instead)
- Problems with sequential dependencies (`Auth must be fixed before Sessions` — can't parallelize)

If you're not sure whether problems are independent: try one investigation first. If fixing it makes others go away, they were related.

## The pattern

### 1. Identify domains

Group the problems by what's actually broken. Each domain becomes one subagent.

```
Domain A: tests/auth/test_session.py       → token refresh races
Domain B: tests/billing/test_invoice.py    → date formatting bug
Domain C: tests/api/test_rate_limit.py     → off-by-one on the limit boundary
```

Three independent domains. No shared state.

### 2. Build per-domain subagent prompts

Each subagent gets:

- **Scope** — exactly which file(s) to look at, exactly which problem to fix
- **Goal** — concrete success criteria (which tests pass, which output appears)
- **Constraints** — explicitly forbid touching other domains' files
- **Output format** — what the subagent must report back

```
You are investigating ONE failing test file: tests/auth/test_session.py.

Other test files (tests/billing/, tests/api/) are being handled by other
agents in parallel. DO NOT modify any file outside the auth subsystem.

Goal: make tests/auth/test_session.py pass. The current failure is a
token refresh race; you'll need to look at src/auth/session.py and
src/auth/middleware.py.

Report back with:
1. Root cause (one sentence)
2. The diff you made
3. Verification command output (fresh, full)
4. Any patterns or gotchas worth filing in vault/

If you find that the cause spans into billing/ or api/, STOP and tell me.
The parallel dispatch assumed independence; if that's wrong I need to
re-coordinate.
```

### 3. Dispatch in parallel

In Claude Code, this means multiple Task tool calls in one assistant turn. They run concurrently. Don't await one before starting the next.

```
[parallel]
  Task("Fix tests/auth/test_session.py")
  Task("Fix tests/billing/test_invoice.py")
  Task("Fix tests/api/test_rate_limit.py")
```

### 4. Integrate the results

When the subagents return:

- Read each summary
- Verify each diff doesn't conflict with the others (`git status` and `git diff`)
- Run the **full** test suite, not just the per-domain ones — this is where you catch the case where two "independent" fixes actually collided
- Capture any cross-cutting patterns or gotchas in vault/

### 5. Final verification

Run the full suite, the linter, the type-checker. The Iron Law of sentinel-verification-before-completion applies — fresh evidence in this message before claiming done.

## Conflict handling

The parallel dispatch *assumes* independence. When the assumption breaks, you'll see one of these:

| Symptom | Likely cause | Response |
|---|---|---|
| Two subagents both modified the same file | Domains weren't actually independent | Re-coordinate. Don't merge the diffs blindly — they may have made contradictory assumptions. |
| Full test suite fails after all subagents reported success | Cross-domain coupling that didn't show in per-domain tests | Investigate the integration failure as a separate problem (not a problem with any single domain) |
| One subagent reports "the cause is in another domain" | Independence assumption was wrong | Stop, re-scope the dispatch |
| All agents return "no changes needed" or all-trivial fixes | The original problems were related, not independent | Sequential investigation would have been faster; learn for next time |

## Anti-patterns

- **Spawning agents for false independence** — running 5 agents on 5 test files that all fail for the same reason. You'll fix the same bug 5 times (or worse, 5 different ways).
- **Granular over-parallelization** — dispatching one agent per failing test instead of per failing module. The dispatch overhead exceeds the speedup.
- **Skipping the full-suite check** — trusting per-domain verification. Cross-domain regressions hide there.
- **Cross-talk between agents** — one agent's mid-flight output influencing another's. Each subagent runs to completion in isolation; orchestrator integrates after.

## Integration

- **Input:** N independent problems
- **Output:** N committed fixes (or N investigation files in vault/) + a confirmed-clean full test suite
- **Verification dependency:** sentinel-verification-before-completion
- **Different from:** sentinel-subagent-driven-development (sequential, plan-driven)
- **Pairs with:** sentinel-iterative-retrieval (per-agent context staging)

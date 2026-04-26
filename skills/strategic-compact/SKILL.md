---
name: sentinel-strategic-compact
description: Use to recommend or trigger /compact at logical task boundaries instead of letting auto-compact fire mid-task. Activates after completing a phase (research → plan, plan → implement, implement → test), after a milestone, after exploring a dead-end, or when context pressure starts to show (responses slowing, recent file edits being forgotten).
origin: sentinel
---

# Strategic Compact

Auto-compact fires at arbitrary points — usually mid-task, sometimes mid-thought. Strategic compact fires at *logical* boundaries, where the loss of conversational detail is recoverable from durable artifacts (the plan file, the spec file, the commit history).

The goal is not to compact more. It is to compact at the **right moments**.

## When to suggest a compact

| Phase transition | Compact? | Why |
|---|---|---|
| Research → Planning | **Yes** | Research is bulky, the plan distills it. The plan file is the durable artifact. |
| Planning → Implementation | **Yes** | The plan is in the file. Free up context for code reasoning. |
| Implementation → Testing | **Sometimes** | Yes if testing is conceptually different work; no if tests reference recently-touched code. |
| Debugging → Next feature | **Yes** | Stack traces and dead-end reasoning are pure noise once resolved. |
| After a failed approach | **Yes** | Clear the dead-end before trying a new path. The investigation file holds the lesson. |
| Mid-implementation | **No** | You'd lose variable names, file paths, and partial state — all costly to reconstruct. |
| Just before commit | **No** | The diff is in your context for a reason. |
| User pivots to unrelated topic | **Yes** | The previous topic's context is purely a distractor for the new one. |

## When NOT to compact (even at a boundary)

- **The next phase needs the artifact contents in head, not on disk** — e.g., you just wrote a long custom prompt that's about to be reused. Save it first, then compact.
- **You're mid-debugging and the failure pattern hasn't crystallized** — compaction discards exactly the chain of attempts that's about to lead to the cause.
- **The conversation is short (<5k tokens)** — nothing to gain.

## The pre-compact checklist

Before calling /compact, ensure these durable artifacts are written:

- [ ] **Spec** — saved to `vault/planning/<topic>-spec.md`?
- [ ] **Plan** — saved to `vault/planning/<topic>-plan.md`?
- [ ] **Decisions** — non-obvious choices captured in `vault/decisions/<topic>.md`?
- [ ] **Investigation** — if debugging, the reasoning chain saved to `vault/investigations/<topic>.md`?
- [ ] **Gotchas** — any pitfalls discovered captured in `vault/gotchas/<name>.md`?
- [ ] **TodoWrite** — current task list reflects actual state (not just historical)?

If any item is unchecked, write it first. The vault is the persistence layer; chat history is volatile. Compaction without writing is just losing work.

## What survives compaction (so you know what's safe to lose)

Survives:
- Anything written to disk (specs, plans, vault entries, code commits)
- The CLAUDE.md content and project memory
- The current TodoWrite state
- A summary of the conversation up to the compact point

Lost:
- Chat-only reasoning that wasn't externalized
- Tool call outputs that weren't acted on
- Visual exploration of files that weren't quoted into a saved artifact

So: if the value of a piece of context is "thinking I did out loud," and it didn't make it into a vault entry or commit, it's lost on compact. Write first.

## Suggesting compact to the user

When you decide a compact is warranted, do not silently call /compact (you can't — it's a user command). Suggest it explicitly with the rationale:

> We've finished the planning phase and the plan is saved to `vault/planning/2026-04-26-auth-plan.md`. Before starting implementation, this is a good moment to `/compact` — the plan file is the durable artifact and we'll free ~30k tokens of brainstorming context for the implementation work.

Three things in that suggestion:
1. **Why** the boundary is a good compact point (phase transition + artifact saved)
2. **What's safe to lose** (brainstorming context that's now in the plan file)
3. **What to gain** (token headroom for the next phase)

The user retains the choice. You provide the reasoning.

## Hook integration (optional)

A PreToolUse hook can count tool calls and surface compact suggestions when activity crosses a threshold. The hook does not auto-compact — it only nudges. See `hooks/optional/` for the pattern (referenced in `commands/config.md` under the `compact_suggest` flag once introduced).

For now, this skill is the model-side discipline. The hook is the optional automation.

## Anti-patterns

- **Compacting on every Stop** — too aggressive. You lose the working set you'll need for the next prompt.
- **Refusing to ever compact** — the auto-compact will then fire mid-task and lose worse things.
- **Compacting without writing** — you've now lost both the chat AND the work. Write the spec, plan, decision, or gotcha first.
- **Treating compact as a productivity move** — it's a context-management move. Don't compact to "feel clean."

## Integration

- **Pairs with:** sentinel-writing-plans (compact after the plan is saved)
- **Pairs with:** sentinel-workflow-bug-fix (compact after the investigation is filed)
- **Pairs with:** sentinel-subagent-driven-development (compact between major task batches)
- **Vault dependency:** the durable artifacts must exist before compaction

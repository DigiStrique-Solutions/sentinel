---
name: sentinel-plan-council
description: Adversarial review of an implementation plan before execution. Spawns a Critic, a Defender, and a Judge as fresh subagents per round, with up to 3 rounds. Uses MAD-M2 masking so each round's Judge only sees the previous round's debate (not the full history) — prevents error compounding. Activates when a plan has `Council required: true`, when scripts/plan-needs-council.sh returns 0, or when a previous plan attempt failed. NOT for code review (use sentinel-workflow-code-review). NOT for deciding which approach to take (use sentinel-brainstorm). For attacking an existing plan to find what will go wrong before execution.
origin: sentinel
---

# Plan Council

Stress-test a plan adversarially before any code is written. The plan goes in; either an approval or a list of specific revisions comes out. The mechanism is structured debate, not a vote.

## Why this exists (the failure mode it fixes)

The first plan you write is rarely the best plan. Single-agent planning suffers from **Degeneration-of-Thought**: once a plan is on the page, the planner anchors on it. Re-reading the plan to "review" it feels productive but rarely surfaces the real problems — the planner's mental model is the same one that produced the plan.

Multi-agent debate breaks the anchor:
- A **Critic** (fresh context, only the spec + plan) attacks the plan
- A **Defender** (fresh context, spec + plan + critique) rebuts the attack
- A **Judge** (fresh context, spec + plan + critique + rebuttal) decides

If the Judge says "approve," the plan was robust enough to survive serious attack.
If the Judge says "revise," you got specific items to fix before execution begins.

Either outcome is better than executing a plan no one tried to break.

## When to use

Triggered by **any** of:

1. The plan header has `Council required: true`
2. `scripts/plan-needs-council.sh <plan_path>` exits 0 (file map > 5 files)
3. A previous attempt at this plan failed and you're re-trying
4. The user explicitly says "council this" / "stress test this plan" / "review the plan first"

Skipped when:
- The plan has `Council required: false` (explicit override)
- The plan touches ≤5 files and there's no previous failure
- The user explicitly says "skip council, just execute"

## When NOT to use

| Don't use plan-council for | Use instead |
|---|---|
| Reviewing existing code | sentinel-workflow-code-review |
| Picking between two design approaches | sentinel-brainstorm |
| Finding bugs in tests | sentinel-adversarial-eval |
| Deciding whether to ship | sentinel-grill-me |
| Reviewing a single function's correctness | direct review, not council |

Council is specifically for **attacking a plan that proposes to change code, before any code changes**.

## The core mechanic: per-round debate with masking

Each round has three subagent calls in sequence:

```
Round N:
  1. Critic subagent
       Inputs: spec, plan, [previous round's revisions if any]
       NOT given: prior round's full debate, prior judge's reasoning
       Output: list of specific weaknesses
  2. Defender subagent
       Inputs: spec, plan, this round's critique
       NOT given: prior rounds' debates
       Output: rebuttal — for each weakness, "addressed because X" or "valid, must fix"
  3. Judge subagent
       Inputs: spec, plan, this round's critique, this round's rebuttal
       NOT given: prior rounds' debates (this is the MAD-M2 mask)
       Output: APPROVE | REVISE: [list of required changes]
```

The MAD-M2 masking — only this round's debate enters the Judge's context — is what keeps compounding errors out. If round 1's Judge made a flawed call, round 2's Judge starts fresh with round 2's debate. Stale reasoning doesn't propagate.

## The outer loop (max 3 rounds)

```
Round 1: Critic → Defender → Judge
  Judge: APPROVE → done (write decision file, return)
  Judge: REVISE → orchestrator writes plan v2 with the revisions, go to Round 2

Round 2: Critic → Defender → Judge (over plan v2, fresh context, no round 1 history)
  Judge: APPROVE → done
  Judge: REVISE → orchestrator writes plan v3, go to Round 3

Round 3: Critic → Defender → Judge (over plan v3)
  Judge: APPROVE → done
  Judge: REVISE → SHIP ANYWAY, log unresolved dissent in decision file
```

The 3-round cap is hard. Council that runs forever isn't council, it's procrastination. After round 3, either approval is reached or the unresolved revisions are written into the decision file and the plan ships.

## Subagent prompt skeletons

### Critic prompt

```
You are reviewing an implementation plan adversarially. Your job is to
find what will go wrong if this plan is executed as written.

Plan:
<paste full plan>

Spec (the requirements the plan claims to satisfy):
<paste spec>

Previous round's required revisions (if any):
<paste, or write "(this is the first round)">

Find concrete weaknesses. For each, name:
1. The specific line / task / file path the problem applies to
2. The failure mode (what breaks when this is executed)
3. The severity: BLOCKER | HIGH | MEDIUM | LOW

Categories to consider:
- Missing tasks (work the plan needs but doesn't include)
- Wrong order (task N depends on task M but M is later)
- Vague steps (steps that require the executor to make a decision)
- Missing verification (claims a task is done without proof)
- Hidden coupling (two tasks both modify the same file in conflicting ways)
- Scope creep (tasks outside the spec)
- Missing rollback / migration paths
- Untested edge cases the spec implies

Do NOT propose solutions. Only identify problems. The Defender's job is
to rebut; yours is to attack.

Format: numbered list, each item with [SEVERITY] and the location.
```

### Defender prompt

```
You are defending an implementation plan against a critique. Your job
is to determine which weaknesses are real (must be fixed) and which are
spurious (already addressed by the plan, just not obviously).

Plan:
<paste full plan>

Spec:
<paste spec>

This round's critique:
<paste full critic output>

For EACH numbered item in the critique, respond:
- "ADDRESSED: <quote from plan that handles this>" — the plan already
  handles this; quote the specific section/line/task that does so
- "VALID: <one-sentence concession>" — the critic is right; this needs
  to be fixed before execution
- "PARTIAL: <what's covered, what isn't>" — half-addressed; specify
  what's still missing

Do NOT speculate about whether the critic is "being too harsh." Decide
each item on the merits. If you concede, concede crisply.

Format: numbered list matching the critique's numbering, each item with
ADDRESSED | VALID | PARTIAL and the supporting evidence.
```

### Judge prompt

```
You are deciding whether an implementation plan is ready for execution.
You have NOT seen previous rounds. You have only this round's debate.

Plan:
<paste full plan>

Spec:
<paste spec>

This round's critique:
<paste critic output>

This round's rebuttal:
<paste defender output>

Decide: APPROVE or REVISE.

APPROVE if:
- All BLOCKER and HIGH items in the critique were either ADDRESSED or
  the rebuttal showed they were already covered
- Any remaining VALID items are MEDIUM or LOW and don't compromise the
  plan's correctness

REVISE if:
- One or more BLOCKER or HIGH items remain VALID after the rebuttal
- The plan has a structural problem the debate identified that can't be
  fixed by minor edits

Output format:
DECISION: APPROVE | REVISE
REASONING: <2-3 sentences>
IF REVISE — REQUIRED CHANGES: <numbered list, each tied to a specific
plan section, written so the orchestrator can apply them mechanically>

Do NOT be diplomatic. Either the plan is ready or it isn't.
```

## Decision file output

After council ends (regardless of outcome), write to:

`vault/decisions/<plan-basename>-council.md`

```markdown
---
plan: vault/planning/2026-04-26-auth-plan.md
date: 2026-04-26
rounds_run: 2
final_decision: APPROVE
---

# Council on auth-plan

## Trigger
explicit_flag (Council required: true in plan header)

## Round 1
**Critic raised:**
- [BLOCKER] Task 3 modifies session.py and Task 5 also modifies session.py — collision
- [HIGH] No rollback path for the migration in Task 6
- [MEDIUM] Steps 4.2 and 4.3 use vague language ("handle the case")

**Defender:**
- 1: VALID — these tasks should be merged
- 2: VALID — needs explicit rollback
- 3: ADDRESSED — quotes the verification command in step 4.4

**Judge: REVISE** (1 BLOCKER + 1 HIGH unresolved)
Required changes:
1. Merge Task 3 and Task 5 into one task with combined steps
2. Add Task 6.5: rollback procedure if migration fails

## Round 2
**Critic raised:**
- [LOW] The new Task 6.5 doesn't say which migration tool to use

**Defender:**
- 1: ADDRESSED — Task 6's tool reference applies to the rollback by extension

**Judge: APPROVE** — no remaining BLOCKER/HIGH items.

## Outcome
Plan approved after 2 rounds. Plan v2 (with Round 1 revisions applied) is the
version executed. See `vault/planning/2026-04-26-auth-plan.md` for the final.
```

If the cap is hit at round 3 with unresolved REVISE items, the file ends with:

```markdown
## Outcome
3-round cap reached with unresolved revisions. SHIPPING ANYWAY per cap.

UNRESOLVED dissent (carried into execution):
- <item>
- <item>

These items become open investigations to monitor during and after execution.
File investigations at vault/investigations/ if any of them surface as actual problems.
```

## Anti-patterns

- **Skipping the masking** — feeding round 2's Judge the round 1 debate. This is the failure mode MAD-M2 was designed to prevent; round 1's stale reasoning will sway round 2 even if it was wrong.
- **The Judge being the Critic** — same model context, same anchor. Each role must be a fresh subagent.
- **Friendly Critic** — a Critic that hedges ("the plan looks pretty good, just a few minor things") is useless. Critic must attack hard. If output reads as gentle, re-dispatch with stronger adversarial framing.
- **Endless rounds** — "let's just one more round." No. Cap at 3.
- **Council on trivial plans** — a 2-file change does not need a 3-round debate. The trigger heuristic exists; respect it.
- **Treating REVISE as failure** — REVISE is the council *working*. The plan was flawed; council found the flaws. That's the value.

## Integration

- **Triggered by:** sentinel-plan-execute (which calls plan-needs-council.sh and routes here when needed)
- **Triggered by:** explicit user request ("council this plan")
- **Required input:** an existing plan at `vault/planning/<topic>-plan.md` and its spec at `vault/planning/<topic>-spec.md`
- **Output:** `vault/decisions/<topic>-council.md` + (if revisions) updated plan
- **Hard cap:** 3 rounds, no exceptions
- **Per-round mask:** each Judge sees only that round's debate (MAD-M2)
- **Different from:** sentinel-grill-me (single interviewer, user-facing) and sentinel-adversarial-eval (for tests/prompts, not plans)

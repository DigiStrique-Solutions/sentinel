---
name: sentinel-iterative-retrieval
description: Use when dispatching subagents that need codebase context they cannot predict upfront. Implements DISPATCH → EVALUATE → REFINE loop, capped at 3 cycles, to progressively narrow what context the subagent receives. Activates when about to spawn a subagent, when a subagent reports "I don't have enough context," or when designing a multi-agent workflow that needs context staging.
origin: sentinel
---

# Iterative Retrieval

When dispatching subagents, you face a paradox: the subagent doesn't know what context it needs until it starts working, but you have to give it context before it starts. Sending everything blows the context window. Sending nothing leaves the agent guessing. Sending what *you* think it needs is often wrong.

The fix is a loop, not a single decision.

## The four phases

```
        ┌──────────────────────┐
        │  1. DISPATCH         │
        │  broad initial query │
        └──────────┬───────────┘
                   ▼
        ┌──────────────────────┐
        │  2. EVALUATE         │
        │  score relevance     │
        └──────────┬───────────┘
                   ▼
        ┌──────────────────────┐
        │  3. REFINE           │
        │  narrow + add gaps   │
        └──────────┬───────────┘
                   ▼
        ┌──────────────────────┐
        │  4. LOOP or PROCEED  │
        │  max 3 cycles        │
        └──────────────────────┘
```

The hard cap on 3 cycles matters. Without it, retrieval becomes its own time sink. After cycle 3, ship the best context you have and let the subagent flag what's still missing.

## Phase 1: Dispatch (broad)

Start wide. Cast a net that's bigger than what you think the subagent needs, because you don't yet know what's relevant. Three sources to combine:

- **Filename/glob match** — `**/*auth*.{ts,py,go}`, `tests/**/*session*`
- **Keyword match in content** — grep for terms from the task spec
- **Structural anchors** — entry point files, the config file, the schema

Goal: 10-20 candidate files, not 200, not 3.

## Phase 2: Evaluate

Score each candidate against the task. The scoring is cheap because you're not reading the files yet — you're reading their **first 30 lines** (the imports + module docstring) and their **filename**.

Per file, ask three questions:

1. **Relevance** — does this file plausibly affect or reveal information about the task?
2. **Information density** — is this a real source file or a re-export / barrel / generated stub?
3. **Gaps** — what does this file reference that I don't have?

Output a relevance ranking (high / medium / low) and a list of unresolved references — names this file imports or calls that point to something not yet in the candidate set.

## Phase 3: Refine

Take action on the evaluation:

- **Drop low-relevance files** — they bloat the context for nothing
- **Pull in the gaps** — every unresolved reference from a high-relevance file becomes a candidate for the next cycle
- **Promote anchors** — if a file is referenced by 3+ high-relevance files, it's a structural anchor; include it even if its own content seems low-relevance

The output of Refine is the input to the next Dispatch — a tighter, smarter candidate set.

## Phase 4: Loop or Proceed

Stop when ANY of these is true:

- The candidate set is stable (no new gaps emerged from the last evaluation)
- The candidate set fits comfortably in the subagent's expected context budget (typically <30k tokens)
- You've completed 3 cycles

When you stop, package the final set as the subagent's context with **explicit citations**:

```
You are working on <task>. The following files are provided as context:

HIGH-RELEVANCE (read first):
- src/auth/session.py    — Session token logic (the function you're modifying lives here)
- src/auth/middleware.py — Where session is verified

REFERENCE (read as needed):
- src/config.py          — Auth-related config keys
- tests/auth/test_session.py — Existing test patterns to follow

NOT INCLUDED but you may need:
- The OAuth provider library docs at <url> — fetch if the implementation
  requires non-trivial use of the library

Task: <full task spec>
```

The "NOT INCLUDED but you may need" line is the safety valve — it tells the subagent *what to ask for* if the context turns out to be insufficient, rather than guessing.

## Anti-patterns

- **Dumping everything** — "Just include the whole src/ directory." This is what iterative-retrieval is designed to prevent. The subagent will be slower, dumber, and more likely to make irrelevant changes.
- **Single-pass retrieval** — running one search and shipping the results without evaluating. The whole point of the loop is that the first pass is wrong.
- **No cap** — looping until the candidate set is "perfect." Ship after 3 cycles regardless. Perfect is the enemy of dispatched.
- **Including tests as context for non-test tasks** — tests are large, repetitive, and rarely the source of truth for behavior. Include them only when the task is to modify or add tests.

## Example

Task: "Add rate limiting to the user signup endpoint."

**Cycle 1 — Dispatch (broad):**
- Glob: `**/*signup*`, `**/*rate*`, `**/*limit*`, `src/api/users.py`
- Result: 14 candidates

**Cycle 1 — Evaluate:**
- HIGH: `src/api/signup.py`, `src/middleware/rate_limit.py` (already exists for login!)
- MEDIUM: `src/api/users.py`, `src/config.py`
- LOW: 10 test files (drop)
- Gaps: `src/middleware/rate_limit.py` imports `RedisStore` — not in candidates

**Cycle 2 — Refine + Dispatch:**
- Add: `src/middleware/rate_limit.py`'s import targets (RedisStore)
- Drop: low-relevance tests
- Result: 6 candidates

**Cycle 2 — Evaluate:**
- All HIGH except `src/api/users.py` (turns out signup is in its own module)
- No new gaps

**Stop after cycle 2.** Ship 5 files to the subagent with the citations format above.

If the subagent had been given all 14 candidates, it would have spent budget reading 8 files of irrelevant tests. If it had been given just `src/api/signup.py`, it would have re-implemented rate limiting from scratch instead of using the existing middleware.

## Integration

- **Used by:** sentinel-subagent-driven-development (before each subagent dispatch when context is non-obvious)
- **Used by:** sentinel-dispatching-parallel-agents (per-agent context staging)
- **Cap:** 3 cycles, no exceptions
- **Output:** packaged context with HIGH/REFERENCE/NOT-INCLUDED sections

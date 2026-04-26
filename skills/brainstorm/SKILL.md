---
name: sentinel-brainstorm
description: Structured exploration before implementation. Activates when building new features, making design decisions, or facing multiple valid approaches. Prevents jumping to code before understanding intent. Explores context, asks clarifying questions, proposes approaches, and produces a spec.
origin: sentinel
---

# Brainstorm

This skill enforces a structured exploration phase before any implementation begins. The core problem it solves: Claude jumps straight to writing code when the user says "build X," but the user's mental model of X and Claude's interpretation of X are often different. The result is technically correct code that misses the intent.

## When to Activate

- User asks to build a new feature or component
- User describes a problem with multiple valid solutions
- User gives a vague or high-level request ("make this better", "add filtering")
- Before any implementation that touches 3+ files
- When the user says "I want to..." or "Can we..." or "What if we..."

## When NOT to Activate

- Single-line fixes, typo corrections, simple renames
- User gives highly specific instructions with exact file paths and code
- Bug fixes (use bug-fix workflow instead)
- User explicitly says "just do it" or "skip brainstorming"

---

## The Process

### Phase 1: Understand Context (read, don't write)

Before proposing anything, understand what exists:

1. **Read the relevant code** — not just the file the user mentioned, but the surrounding area. How does the current system work? What patterns does it use?
2. **Check the vault** — are there architectural decisions, gotchas, or past investigations related to this area?
3. **Check for prior art** — does something similar already exist in the codebase that can be extended rather than built from scratch?

Do NOT propose solutions during this phase. Just gather context.

### Phase 2: Clarify Intent (ask, don't assume)

Ask the user focused questions to resolve ambiguity. Rules:

- **One question at a time.** Don't dump a list of 10 questions. Ask the most important one, wait for the answer, then ask the next if needed.
- **Offer options, not open-ended questions.** Instead of "What do you want?" ask "Should this be a modal dialog or a sidebar panel? The sidebar fits the existing pattern."
- **Show your understanding.** Before asking, state what you think the user wants. Let them correct you.
- **Stop after 3 questions max.** If the intent is still unclear after 3 questions, propose 2 approaches and let the user pick.

### Phase 3: Propose Approaches (2-3 options, not 1)

Present 2-3 distinct approaches with trade-offs:

```
Approach A: [Name]
  How: [1-2 sentence description]
  Pros: [what's good about it]
  Cons: [what's risky or costly]
  Files: [which files would change]

Approach B: [Name]
  How: [1-2 sentence description]
  Pros: [what's good about it]
  Cons: [what's risky or costly]
  Files: [which files would change]

Recommendation: [A or B] because [reason]
```

Rules for proposals:
- **Each approach must be meaningfully different.** Not "do it with a for loop" vs "do it with a while loop." Different architectures, different patterns, different trade-offs.
- **Include file paths.** The user needs to know the blast radius before choosing.
- **State your recommendation.** Don't be neutral — tell the user which you'd pick and why. But accept their choice.

### Phase 4: Write Spec (if user approves)

Once the user picks an approach, write a brief spec before coding:

```
## Spec: [Feature Name]

### What
[1-2 sentences describing what will be built]

### Approach
[The chosen approach from Phase 3]

### Changes
- [ ] [File 1] — [what changes]
- [ ] [File 2] — [what changes]
- [ ] [File 3] — [what changes]

### Not Doing
- [Explicitly list what's out of scope]

### Verification
- [How to verify this works — specific test or command]
```

The spec serves two purposes:
1. **Alignment check** — the user can correct misunderstandings before code is written
2. **TodoWrite seed** — the changes list becomes the task checklist

### Phase 5: Transition to Execution

After the user approves the spec:

1. Create a TodoWrite checklist from the spec's changes list
2. Transition to the appropriate workflow (new-feature, feature-improvement, refactor)
3. Begin TDD: write the first failing test for the first task

---

## Anti-Patterns to Avoid

### 1. Premature Implementation
**Wrong:** User says "add a search bar" → Claude immediately creates SearchBar.tsx
**Right:** User says "add a search bar" → Claude asks "Should this search the current page content or make an API call? The existing list components use client-side filtering."

### 2. Single Approach
**Wrong:** "Here's how we'll implement this" → one approach with no alternatives
**Right:** "Two ways to approach this: A uses the existing filter pattern, B adds a dedicated search endpoint. I'd recommend A because..."

### 3. Question Dump
**Wrong:** "Before I start, can you answer these 8 questions: 1) ... 2) ... 3) ..."
**Right:** "Should this filter results in real-time as the user types, or only on submit? The current pattern uses debounced real-time filtering."

### 4. Fake Options
**Wrong:** "Option A: Good approach. Option B: Same approach but worse."
**Right:** "Option A: Client-side filtering (fast, works offline, limited to loaded data). Option B: Server-side search (handles large datasets, requires API endpoint, adds latency)."

### 5. Skipping to Code
**Wrong:** "Let me just quickly code this up and you can see if it's right"
**Right:** "Let me understand the requirements first, then propose an approach for your approval"

---

## Integration with Sentinel Workflows

After brainstorming completes and the spec is approved:

- **For most implementation work** → invoke `sentinel-writing-plans` to decompose the spec into bite-sized 2-5 minute tasks. The plan file becomes the input to either `sentinel-subagent-driven-development` (preferred when subagents are available) or `sentinel-executing-plans`.
- **Feature improvement** → transition to `vault/workflows/feature-improvement.md` (step 2: Define)
- **Refactor** → transition to `vault/workflows/refactor.md` (step 1: Understand)
- **Research needed** → transition to `vault/workflows/research-spike.md`

The brainstorm output is a **spec**, not a plan. The spec answers "what should we build and why." The plan answers "what's the exact sequence of file edits to build it." Don't conflate the two — see `sentinel-writing-plans` for the plan-vs-spec distinction.

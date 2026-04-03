---
name: sentinel-methodology
description: Core methodology for disciplined software development. Activates when investigating bugs, managing knowledge vaults, recovering sessions, or running quality gates. Enforces investigation journals, self-healing knowledge loops, session continuity, and gate-based verification.
origin: sentinel
---

# Sentinel Methodology

The core discipline framework for sustainable, high-quality software development. This skill codifies the practices that prevent context pollution, knowledge decay, and silent regressions.

## When to Activate

- Starting a debugging session or investigation
- Managing a knowledge vault (gotchas, decisions, investigations)
- Recovering from a crashed or compacted session
- Running pre-commit or pre-merge quality verification
- Any multi-step task where progress tracking matters

---

## 1. Investigation Journal Protocol

### When to Create

Create an investigation journal **immediately** when:
- A fix attempt fails for a non-obvious reason
- You are debugging a problem with multiple possible causes
- You need to try more than one approach

### File Location and Naming

```
vault/investigations/YYYY-MM-<brief-slug>.md
```

Examples:
- `vault/investigations/2026-04-auth-token-refresh.md`
- `vault/investigations/2026-04-sse-event-ordering.md`

### Journal Format

```markdown
# Investigation: <Title>

**Status:** in-progress | resolved | escalated
**Area:** <module or subsystem>
**Started:** YYYY-MM-DD
**Resolved:** YYYY-MM-DD (if applicable)

## Problem Statement
<What is happening? What is expected? What is observed?>

## Attempt 1
**Hypothesis:** <What you think is wrong and why>
**What was tried:** <Exact steps taken>
**Result:** <What happened>
**Why it failed:** <Root cause of failure, not just "it didn't work">

## Attempt 2
**Hypothesis:** ...
**What was tried:** ...
**Result:** ...
**Why it failed:** ...

## Root Cause (when resolved)
<The actual root cause>

## Fix Applied (when resolved)
<What fixed it and why>
```

### The Two-Failure Stop Rule

After **two failed attempts** on the same problem:

1. **STOP immediately.** Do not attempt a third approach.
2. Save the investigation journal with both attempts documented.
3. Tell the user: "Two approaches have failed. The context may be polluted with failed reasoning. Recommend clearing context and restarting with a focused prompt."
4. Summarize what was tried and why it failed so the fresh session can skip dead ends.
5. The investigation file persists across session clears -- it is the bridge.

### Rules

- Investigation files are **append-only during debugging.** Never delete attempt entries.
- Each attempt must explain **WHY** it failed, not just that it failed.
- When resolved, fill in the Root Cause and Fix Applied sections.
- Never silently move on from a failed attempt without documenting it.

---

## 2. Self-Healing Vault Loop

The knowledge vault is only useful if it is accurate. Stale information actively misleads future sessions. This protocol ensures the vault stays current.

### What Goes in the Vault

| Entry Type | Location | When to Create |
|------------|----------|----------------|
| Gotcha | `vault/gotchas/` | Non-obvious constraint or pitfall discovered |
| Decision | `vault/decisions/` | Architectural choice with trade-offs |
| Investigation | `vault/investigations/` | Bug with multiple attempted approaches |
| Completed Work | `vault/completed/` | Significant feature or migration finished |

### Staleness Detection

After completing **any task** that changes the codebase, run the staleness check:

#### Step 1: Check Gotchas
Read filenames in `vault/gotchas/`. For each one related to the area just changed:
- Is this gotcha still true?
- Did the fix eliminate the underlying issue?
- If the gotcha is now wrong, **delete it** or update it.

#### Step 2: Check Decisions
Read filenames in `vault/decisions/`. For each one related to the area just changed:
- Is this decision still in effect?
- Did the change supersede it?
- If superseded, update status to "Superseded by ADR-NNN" and add the new ADR.

#### Step 3: Check Investigations
Read filenames in `vault/investigations/`. For each open investigation:
- Does the fix resolve it?
- If yes, update status to "resolved" and fill in the root cause.

#### Step 4: Check Completed Entries
If the work makes a previous "Remaining Work" section obsolete, update it.

### Gotcha Lifecycle

```
Discovery → Create gotcha file → Reference in future sessions → Fix lands → Delete gotcha
```

Gotchas are **ephemeral by design.** When the underlying issue is fixed, the gotcha becomes noise. Delete it.

### Decision Lifecycle

```
Choice made → Create ADR → Reference in future decisions → Superseded → Mark as superseded (never delete)
```

ADRs are **never deleted**, only superseded. They form the historical record of why the system is shaped the way it is.

---

## 3. Session Continuity

### Pre-Compact Save

Before context compaction or session end, save critical state:

```markdown
# Session State: YYYY-MM-DD

## What I Was Working On
<Current task description>

## Current Status
<Where I am in the task>

## Files Modified
<List of files changed and why>

## Key Decisions Made
<Any decisions that would be lost on compaction>

## Open Questions
<Anything unresolved>

## Next Steps
<What should happen next>
```

Save to: `vault/session-logs/YYYY-MM-DD-<slug>.md`

### Session Recovery Protocol

When resuming work after a session break:

1. Read the most recent file in `vault/session-logs/`
2. Read any open investigations in `vault/investigations/`
3. Check `vault/gotchas/` for the area being worked on
4. Check `vault/decisions/` for architectural context
5. Review git log for recent commits
6. Resume from the "Next Steps" section of the session log

### Resume Checklist

- [ ] Session log read and understood
- [ ] Open investigations reviewed
- [ ] Relevant gotchas checked
- [ ] Git state verified (branch, uncommitted changes)
- [ ] Next steps clear before writing code

---

## 4. Quality Gate Framework

Seven gates that must pass before declaring work complete. Execute sequentially. If any gate fails, fix the issue before proceeding.

### Gate 1: Tests Pass

- [ ] All existing tests still pass
- [ ] New tests written for new or changed behavior
- [ ] Tests follow the project's test standards

### Gate 2: No Anti-Patterns

- [ ] Review anti-pattern list (see skill: quality-patterns)
- [ ] Confirm none of the listed anti-patterns are present in the change
- [ ] If tempted to add a workaround, STOP and discuss with user first

### Gate 3: Correct, Not Safe

- [ ] The fix or feature actually solves the stated problem
- [ ] Not a workaround that masks the real issue
- [ ] No try/catch blocks that silently swallow errors
- [ ] No new parameters added just to bypass logic
- [ ] If unsure whether the approach is correct, state the uncertainty explicitly

### Gate 4: Architecture Alignment

- [ ] Change follows existing patterns
- [ ] If deviating from patterns, document why as an ADR
- [ ] File sizes under 800 lines, functions under 50 lines
- [ ] Immutability preserved (new objects returned, no mutation)

### Gate 5: Completeness

- [ ] Error handling for failure cases (not just happy path)
- [ ] Input validation at system boundaries
- [ ] Structured logging for debuggability
- [ ] No TODO/FIXME/HACK left in code (unless explicitly accepted by user)
- [ ] No hardcoded secrets, IDs, or environment-specific values

### Gate 6: Self-Review

- [ ] Read the full diff as if reviewing someone else's code
- [ ] Check for: unused imports, dead code, commented-out code, debug statements
- [ ] Run linter on changed files
- [ ] Verify no files were accidentally modified outside the intended scope

### Gate 7: Vault Maintenance

- [ ] If any fix attempts failed before succeeding, logged in `vault/investigations/`
- [ ] If a non-obvious behavior was discovered, added to `vault/gotchas/`
- [ ] If an architectural decision was made, added to `vault/decisions/`
- [ ] Staleness check completed (see section 2)
- [ ] If an open investigation is now resolved, update its status

### Gate Execution

After completing work, go through each gate sequentially. If any gate fails, fix the issue before proceeding. Do not declare work complete with any gate unchecked.

If a gate cannot be satisfied (e.g., no test infrastructure for a specific area), explicitly tell the user which gate was skipped and why.

---

## 5. Vault Maintenance Protocol

### Write Immediately, Not at the End

If a fix attempt fails, document it **NOW**, not after three more attempts. The investigation journal is your safety net against context pollution.

### Investigation Files Are Append-Only During Debugging

Never delete attempt entries from an active investigation. They record what NOT to try. This is as valuable as recording what works.

### Gotcha Files Can Be Deleted

If the underlying issue is fixed, the gotcha is noise. Delete it. Do not accumulate stale warnings.

### ADRs Are Never Deleted, Only Superseded

Change status to "Superseded by ADR-NNN". The historical record matters.

### Deep Cleanup

Periodically review the full vault for:
- Orphaned investigation files (resolved but not marked)
- Stale gotchas (underlying issues long since fixed)
- Superseded decisions (not marked as such)
- Completed entries with outdated "Remaining Work" sections

---

## 6. No Premature Completion Claims

### The Iron Law

```
NO COMPLETION CLAIMS WITHOUT FRESH VERIFICATION EVIDENCE
```

If you haven't run the verification command in this response, you cannot claim it passes.

### Forbidden Patterns

Never say any of these without fresh evidence in the same message:
- "All tests pass" — without showing the test output
- "The fix is complete" — without running verification
- "Everything looks good" — without checking
- "Done!" — without evidence

### What to Do Instead

1. **Run the verification command** (test, lint, build, type check)
2. **Read the output** — check exit code, count failures
3. **State the result with evidence** — "pytest ran 47 tests, all passed (exit 0)"
4. If it failed, say so. False confidence is worse than honest failure.

---

## Key Principles

1. **Wrong information is worse than no information.** A stale gotcha actively misleads. Delete it.
2. **Two failures means stop.** Context pollution is real. A fresh session with an investigation file is faster than a fifth attempt.
3. **Write immediately.** The moment something unexpected happens, document it. Not later. Now.
4. **Tests are truth, not self-assessment.** If you cannot write a verification command for a unit of work, the unit is too vague.
5. **The vault is a living system.** It requires active maintenance, not just passive accumulation.
6. **Evidence before claims, always.** No completion claims without running the verification command first. Claiming without evidence is lying, not efficiency.
7. **No fixes without root cause.** If you don't understand why it's broken, you can't fix it. Symptom fixes create new bugs.

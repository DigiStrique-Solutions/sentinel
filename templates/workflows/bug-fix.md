# Bug Fix Workflow

Step-by-step process for fixing bugs. Follow every step in order.

**The Iron Law: NO FIXES WITHOUT ROOT CAUSE INVESTIGATION FIRST.**
If you haven't completed steps 1-2, you cannot propose fixes. Symptom fixes are failure.

## 1. Understand

- [ ] Read the error message / user report completely — don't skip past errors or warnings
- [ ] Read stack traces completely — note line numbers, file paths, error codes
- [ ] Identify which module or service is affected
- [ ] Read the relevant architecture docs in `vault/architecture/`
- [ ] Check `vault/gotchas/` for known pitfalls in that area
- [ ] Check `vault/decisions/` for context on why the code is structured this way
- [ ] **Check `vault/investigations/` for past debugging sessions in this area** — someone may have already tried the obvious fix and documented why it doesn't work
- [ ] Check recent changes: `git log --oneline -10`, `git diff HEAD~3` — what changed that could cause this?

## 2. Reproduce and Trace

- [ ] Can you trigger the bug reliably? What are the exact steps?
- [ ] If not reproducible — gather more data, don't guess
- [ ] Trace the code path from entry point to failure
- [ ] Read the actual source code (not just the error line — read the full function and its callers)
- [ ] **Find working examples** — locate similar working code in the same codebase. What works that's similar to what's broken?
- [ ] **Compare broken vs working** — list every difference, however small. Don't assume "that can't matter"
- [ ] Identify the root cause, not just the symptom
- [ ] If there's a test file for the affected module, read it to understand expected behavior

### For multi-component systems (API → service → database, CI → build → deploy):

Before proposing fixes, add diagnostic instrumentation:
- [ ] For EACH component boundary: log what data enters, log what data exits
- [ ] Run once to gather evidence showing WHERE it breaks
- [ ] Analyze evidence to identify the failing component
- [ ] THEN investigate that specific component

### Red flags — STOP and return to step 1:

If you catch yourself thinking any of these, you are skipping root cause investigation:
- "Quick fix for now, investigate later"
- "Just try changing X and see if it works"
- "It's probably X, let me fix that"
- "I don't fully understand but this might work"
- "Here are the main problems: [lists fixes without investigation]"
- Proposing solutions before tracing data flow

**ALL of these mean: STOP. You don't understand the problem yet.**

## 3. Write Failing Test (RED)

- [ ] Write a test that reproduces the bug
- [ ] Run it — confirm it **fails**
- [ ] The test must fail for the RIGHT reason (the actual bug), not a setup issue
- [ ] Follow test standards in `vault/quality/test-standards.md`

```bash
# Run the specific test
pytest tests/path/to/test.py -x -v          # Python
npm test -- path/to/test.ts                  # TypeScript
```

## 4. Fix (GREEN)

- [ ] State your hypothesis clearly: "I think X is the root cause because Y"
- [ ] Make the **minimal** change to fix the bug — one variable at a time
- [ ] Do NOT refactor surrounding code — fix only the bug
- [ ] Do NOT add workarounds (see `vault/quality/anti-patterns.md`)
- [ ] Run the failing test — confirm it **passes**
- [ ] Run the full test suite for the affected module

### If the fix attempt FAILS:

**Do not silently move on.** Immediately document the failed attempt:

1. Create `vault/investigations/YYYY-MM-<brief-slug>.md` (use the template)
2. Log: what you hypothesized, what you tried, what happened, WHY it failed
3. Then try the next approach — add each attempt to the same file
4. This prevents future sessions from repeating the same dead ends

### After 2 failed attempts: STOP

If two approaches have failed, the context is likely polluted with failed reasoning. Do not keep trying.
1. Tell the user: "Two approaches failed. Context may be polluted."
2. Suggest: `/clear` and restart with a better-scoped prompt
3. Summarize what was tried and why it failed so the fresh session can skip dead ends
4. Save the investigation file — it persists across `/clear`

### After 3 failed attempts: Question the architecture

If three fixes have failed (across sessions), the problem may not be the code — it may be the architecture:
- Each fix reveals new shared state, coupling, or problems in a different place
- Fixes require "massive refactoring" to implement
- Each fix creates new symptoms elsewhere

**STOP and discuss fundamentals with the user** before attempting more fixes. This is not a failed hypothesis — this is a wrong architecture.

## 5. Verify

- [ ] Read `vault/quality/gates.md` — pass all gates
- [ ] Run linter
- [ ] If the fix changes behavior, check if other tests need updating
- [ ] If the fix touches an API contract, check contract tests

## 6. Document & Heal the Vault

- [ ] If this was a non-obvious bug, add to `vault/gotchas/`
- [ ] If the fix involved an architectural decision, add to `vault/decisions/`
- [ ] If an investigation was opened, update its status to `resolved`
- [ ] **Staleness check** (see `vault/workflows/vault-maintenance.md`):
  - [ ] Are any existing gotchas now wrong because of this fix?
  - [ ] Are any existing decisions now superseded?
  - [ ] Are any open investigations now resolved?
  - [ ] Delete or update stale entries — don't leave lies in the vault
- [ ] Commit with `fix:` prefix: `fix: <what was fixed and why>`

#workflow #bug-fix

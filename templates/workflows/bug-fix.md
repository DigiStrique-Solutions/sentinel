# Bug Fix Workflow

Step-by-step process for fixing bugs. Follow every step in order.

## 1. Understand

- [ ] Read the error message / user report completely
- [ ] Identify which module or service is affected
- [ ] Read the relevant architecture docs in `vault/architecture/`
- [ ] Check `vault/gotchas/` for known pitfalls in that area
- [ ] Check `vault/decisions/` for context on why the code is structured this way
- [ ] **Check `vault/investigations/` for past debugging sessions in this area** -- someone may have already tried the obvious fix and documented why it doesn't work

## 2. Reproduce

- [ ] Trace the code path from entry point to failure
- [ ] Read the actual source code (not just the error line -- read the full function and its callers)
- [ ] Identify the root cause, not just the symptom
- [ ] If there's a test file for the affected module, read it to understand expected behavior

## 3. Write Failing Test (RED)

- [ ] Write a test that reproduces the bug
- [ ] Run it -- confirm it **fails**
- [ ] The test must fail for the RIGHT reason (the actual bug), not a setup issue
- [ ] Follow test standards in `vault/quality/test-standards.md`

```bash
# Run the specific test
pytest tests/path/to/test.py -x -v          # Python
npm test -- path/to/test.ts                  # TypeScript
```

## 4. Fix (GREEN)

- [ ] Make the **minimal** change to fix the bug
- [ ] Do NOT refactor surrounding code -- fix only the bug
- [ ] Do NOT add workarounds (see `vault/quality/anti-patterns.md`)
- [ ] Run the failing test -- confirm it **passes**
- [ ] Run the full test suite for the affected module

### If the fix attempt FAILS:

**Do not silently move on.** Immediately document the failed attempt:

1. Create `vault/investigations/YYYY-MM-<brief-slug>.md` (use the template)
2. Log: what you hypothesized, what you tried, what happened, WHY it failed
3. Then try the next approach -- add each attempt to the same file
4. This prevents future sessions from repeating the same dead ends

### After 2 failed attempts: STOP

If two approaches have failed, the context is likely polluted with failed reasoning. Do not keep trying.
1. Tell the user: "Two approaches failed. Context may be polluted."
2. Suggest: `/clear` and restart with a better-scoped prompt
3. Summarize what was tried and why it failed so the fresh session can skip dead ends
4. Save the investigation file -- it persists across `/clear`

## 5. Verify

- [ ] Read `vault/quality/gates.md` -- pass all gates
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
  - [ ] Delete or update stale entries -- don't leave lies in the vault
- [ ] Commit with `fix:` prefix: `fix: <what was fixed and why>`

#workflow #bug-fix

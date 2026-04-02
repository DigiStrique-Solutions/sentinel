# Quality Gates

Claude Code MUST pass ALL gates before declaring work complete. Do not skip gates.

## Gate 1: Tests Pass

- [ ] All existing tests still pass
- [ ] New tests written for new/changed behavior
- [ ] Tests follow standards in `vault/quality/test-standards.md`

```bash
# Python
pytest tests/ -x -v

# TypeScript
npm test
# or
yarn test
```

## Gate 2: No Anti-Patterns

- [ ] Re-read `vault/quality/anti-patterns.md`
- [ ] Confirm NONE of the 10 listed anti-patterns are present in the change
- [ ] If tempted to add a workaround, STOP and discuss with user first

## Gate 3: Correct, Not Safe

- [ ] The fix/feature actually solves the stated problem
- [ ] Not a workaround that masks the real issue
- [ ] No `try/except` blocks that silently swallow errors
- [ ] No new parameters added just to bypass logic (e.g., `skip_validation=True`)
- [ ] If unsure whether the approach is correct, state the uncertainty explicitly to the user

## Gate 4: Architecture Alignment

- [ ] Change follows existing patterns (check `vault/architecture/`)
- [ ] If deviating from patterns, document why in `vault/decisions/` as an ADR
- [ ] File sizes under 800 lines, functions under 50 lines
- [ ] Immutability preserved (new objects returned, no mutation)

## Gate 5: Completeness

- [ ] Error handling for failure cases (not just happy path)
- [ ] Input validation at system boundaries
- [ ] Logging for debuggability (structured logging, not print statements)
- [ ] No TODO/FIXME/HACK left in code (unless explicitly accepted by user)
- [ ] No hardcoded secrets, IDs, or environment-specific values

## Gate 6: Self-Review

- [ ] Read the full diff as if reviewing someone else's code
- [ ] Check for: unused imports, dead code, commented-out code, debug statements
- [ ] Run linter:
  - Python: `ruff check src/` or `flake8 src/`
  - TypeScript: `eslint src/` or `yarn lint`
- [ ] Verify no files were accidentally modified outside the intended scope

## Gate 7: Vault Maintenance

- [ ] If any fix attempts failed before succeeding, logged in `vault/investigations/`
- [ ] If a non-obvious behavior was discovered, added to `vault/gotchas/`
- [ ] If an architectural decision was made, added to `vault/decisions/`
- [ ] **Staleness check:** scan `vault/gotchas/` and `vault/decisions/` for entries related to the area you changed -- delete or update anything that is now wrong
- [ ] If an open investigation in `vault/investigations/` is now resolved, update its status

See `vault/workflows/vault-maintenance.md` for the full protocol.

## How to Use

After completing work, go through each gate sequentially. If any gate fails, fix the issue before proceeding. Do not declare work complete with any gate unchecked.

If a gate cannot be satisfied (e.g., no test infrastructure for a specific area), explicitly tell the user which gate was skipped and why.

#quality #gates

# Feature Improvement Workflow

Improving an existing feature -- not building from scratch (use `new-feature.md`) and not fixing a bug (use `bug-fix.md`). You're modifying working code to make it better.

## Examples

- Adding a filter to an existing list view
- Improving error messages in an existing flow
- Adding a new column to an existing table
- Enhancing an existing API endpoint with new parameters
- Improving UX of an existing feature (loading states, feedback, copy)

## 1. Understand Current Behavior

- [ ] Read the existing implementation completely (not just the area you're changing)
- [ ] Read existing tests to understand expected behavior
- [ ] Read relevant architecture docs in `vault/architecture/`
- [ ] Check `vault/gotchas/` for pitfalls in this area
- [ ] Check `vault/decisions/` for why the current implementation exists
- [ ] **Check `vault/investigations/` for past debugging** -- the improvement might re-introduce a previously fixed issue

## 2. Define the Improvement

- [ ] What specific behavior changes? (be precise -- "better" is not a spec)
- [ ] What stays the same? (explicitly list preserved behaviors)
- [ ] Are there backward compatibility concerns? (existing API consumers, stored data)
- [ ] Does this change the API contract? (if yes, consider versioning or migration)

## 3. Write / Update Tests (RED)

- [ ] Write new tests for the NEW behavior
- [ ] Verify existing tests still describe the PRESERVED behavior
- [ ] If existing tests need updating (because behavior intentionally changed), update them
- [ ] Run all tests -- new tests should **fail**, existing tests should **pass**
- [ ] Follow test standards in `vault/quality/test-standards.md`

## 4. Implement (GREEN)

- [ ] Make the minimal changes needed for the improvement
- [ ] Follow existing patterns -- don't introduce new patterns for one change
- [ ] Don't refactor surrounding code (that's a separate task -- see `refactor.md`)
- [ ] Read `vault/quality/anti-patterns.md` -- use none of the listed patterns
- [ ] Run tests -- all should **pass** (new + existing)

### If the improvement changes API behavior:
- [ ] Update contract tests if endpoint signature changed
- [ ] Update API clients on the consumer side
- [ ] Verify backward compatibility (old clients still work)

## 5. Verify

- [ ] All tests pass (new + existing + unrelated)
- [ ] Read `vault/quality/gates.md` -- pass all gates
- [ ] Run linter

## 6. Document

- [ ] If the improvement changes how things work, update `vault/architecture/`
- [ ] If backward compatibility was a consideration, add to `vault/decisions/`
- [ ] If a non-obvious constraint was discovered, add to `vault/gotchas/`
- [ ] **Staleness check:** did this improvement make any existing gotchas or decisions obsolete?
- [ ] Commit with appropriate prefix: `feat:` (new capability) or `fix:` (improved existing)

## Key Differences from New Feature

| | New Feature | Feature Improvement |
|---|---|---|
| Starting point | Nothing exists | Working code exists |
| Tests | All new | Mix of new + updated existing |
| Backward compat | Not a concern | Must preserve unless explicitly breaking |
| Scope risk | Over-building | Breaking existing behavior |
| Refactoring | Part of the process | Separate task, not mixed in |

#workflow #feature #improvement

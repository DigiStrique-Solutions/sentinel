# New Feature Workflow

Step-by-step process for implementing new features. Follow every step in order.

## 1. Research

- [ ] Read the relevant architecture files in `vault/architecture/`
- [ ] Check `vault/decisions/` for past decisions that affect this area
- [ ] **Check `vault/investigations/` for past debugging sessions** -- learn from prior failed approaches before writing code
- [ ] Search for existing implementations that can be reused
- [ ] Identify which files will need to change

## 2. Plan

- [ ] Break the feature into discrete steps
- [ ] Identify dependencies between steps
- [ ] For complex features (3+ files, new patterns), use Plan Mode
- [ ] Present the plan to the user before writing code
- [ ] Identify which existing patterns to follow (check `vault/architecture/`)

## 3. Write Tests First (RED)

- [ ] For each component of the feature, write tests BEFORE implementation
- [ ] Follow test standards in `vault/quality/test-standards.md`
- [ ] Include: happy path, error cases, edge cases
- [ ] Run tests -- confirm they **fail** (because implementation doesn't exist yet)

## 4. Implement (GREEN)

- [ ] Write the minimal implementation to make tests pass
- [ ] Follow existing patterns in the codebase
- [ ] Read `vault/quality/anti-patterns.md` -- use NONE of the listed patterns
- [ ] Run tests after each component -- confirm they **pass**

### If implementation hits unexpected failures

**Do not silently try another approach.** Document what failed:

1. Create or update `vault/investigations/YYYY-MM-<brief-slug>.md`
2. Log: hypothesis, what was tried, what happened, WHY it failed
3. Each failed attempt is an entry -- append, never delete
4. This prevents future sessions from repeating the same dead ends

**After 2 failed attempts: STOP.** Tell the user the context may be polluted. Suggest `/clear` and a fresh start. Save the investigation file -- it persists across `/clear`.

## 5. Refactor (IMPROVE)

- [ ] Clean up implementation without changing behavior
- [ ] Ensure files stay under 800 lines
- [ ] Ensure functions stay under 50 lines
- [ ] Remove any duplicate code
- [ ] Verify immutability (new objects, no mutation)

## 6. Verify

- [ ] Read `vault/quality/gates.md` -- pass all gates
- [ ] Run the full test suite (not just new tests)
- [ ] Run linter

## 7. Document & Heal the Vault

- [ ] If the feature introduces new patterns, add to `vault/decisions/`
- [ ] If any gotchas were discovered, add to `vault/gotchas/`
- [ ] If an investigation was opened, update its status to `resolved`
- [ ] **Staleness check** (see `vault/workflows/vault-maintenance.md`):
  - [ ] Are any existing gotchas now wrong because of this change?
  - [ ] Are any existing decisions now superseded?
  - [ ] Are any open investigations now resolved?
  - [ ] Delete or update stale entries -- don't leave lies in the vault
- [ ] Commit with `feat:` prefix

#workflow #feature

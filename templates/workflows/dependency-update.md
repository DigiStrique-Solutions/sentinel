# Dependency Update Workflow

Updating packages and external dependencies safely.

## 1. Audit Current State

- [ ] Run dependency audit tool for known vulnerabilities
- [ ] Check for outdated packages
- [ ] List packages to update and classify by risk

## 2. Classify Updates

| Category | Risk | Approach |
|----------|------|----------|
| **Patch** (1.2.3 -> 1.2.4) | Low | Update, run tests, ship |
| **Minor** (1.2.3 -> 1.3.0) | Medium | Read changelog, update, run tests |
| **Major** (1.2.3 -> 2.0.0) | High | Read migration guide, plan, test thoroughly |
| **Security fix** | Urgent | Prioritize regardless of version bump |

## 3. Update Process

For each dependency:

- [ ] Read the changelog/release notes
- [ ] Check for breaking changes
- [ ] Update the dependency
- [ ] Run the full test suite for the affected project
- [ ] If tests fail, check if the failure is due to the update or pre-existing

## 4. Post-Update Verification

- [ ] All existing tests pass
- [ ] No new type errors
- [ ] No new lint warnings
- [ ] Application starts and runs correctly
- [ ] Critical user flows still work

## 5. Document

- [ ] If an update introduced a new constraint, add to `vault/gotchas/`
- [ ] If a major version upgrade required significant changes, add to `vault/decisions/`
- [ ] Commit with `chore:` prefix for routine updates, `fix:` for security patches

#workflow #dependencies #update

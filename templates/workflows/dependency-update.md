# Dependency Update Workflow

Updating packages and external dependencies safely.

## 1. Audit Current State

```bash
# Python
pip audit                    # Known vulnerabilities
pip list --outdated          # Available updates

# Node
npm audit                   # Known vulnerabilities
npm outdated                # Available updates
# or
yarn audit
yarn outdated
```

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

### Python:
```bash
pip install package==new_version
# Update requirements.txt or pyproject.toml
pytest tests/ -x
```

### Node:
```bash
npm install package@new_version
# or
yarn upgrade package@new_version
npm test
npx tsc --noEmit
```

## 4. Post-Update Verification

- [ ] All existing tests pass
- [ ] No new type errors
- [ ] No new lint warnings
- [ ] Application starts and basic flows work

## 5. External API Version Changes

If an external API you depend on is deprecating a version:

- [ ] Identify which code paths are affected
- [ ] Check the API migration guide
- [ ] Update API calls (endpoints, parameters, response parsing)
- [ ] Update tests with new response shapes
- [ ] Verify the new API paths work

## 6. Document

- [ ] If an API change introduced a new constraint, add to `vault/gotchas/`
- [ ] If a major version upgrade required significant changes, add to `vault/decisions/`
- [ ] Update `vault/changelog/` with the dependency updates

#workflow #dependencies #update

---
name: sentinel-workflow-dependency-update
description: Safe dependency-update workflow — audit, classify, update, verify, document. Use whenever the user says "update packages", "bump dependencies", "upgrade library", "npm audit", "pip audit", "security patch", "CVE", "outdated deps", "upgrade to vN", or otherwise signals a package or external-API version change — even if they don't explicitly say "workflow". Enforces changelog review before every update, classifies updates by risk (patch/minor/major/security), and documents gotchas or decisions in the vault. Six steps — audit, classify, update, verify, API version changes, document.
workflow: true
workflow-steps: 6
allowed-tools: Read Grep Glob Bash Edit Write MultiEdit TodoWrite
origin: sentinel
---

# Dependency Update Workflow

Updating packages and external dependencies safely.

This is a Sentinel workflow skill. When it activates, the `sentinel-workflow-runner` protocol drives execution — creates a run directory, checkpoints progress after each step, and supports resumption across sessions. You do not need to invoke the runner explicitly; it activates alongside this skill.

## Protocol summary

At the top of the workflow, create a new run:

```bash
RUN_ID=$(bash "${CLAUDE_PLUGIN_ROOT}/scripts/workflow-state.sh" start dependency-update)
```

Before each numbered step, call `step-start`. After each step completes, call `step-complete` (with an artifact path if you produced one). After the final step, call `finish <run-id> completed`. On failure, call `step-fail` and follow the failure-handling rules in each section below.

Full protocol details: see `sentinel-workflow-runner` skill.

---

## 1. Audit Current State

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/workflow-state.sh" step-start "$RUN_ID" 1 "Audit Current State"
```

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

**Write an artifact**: `vault/workflows/runs/$RUN_ID/artifacts/step-1-audit.md` with the raw audit output and a list of packages flagged as outdated or vulnerable.

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/workflow-state.sh" step-complete "$RUN_ID" 1 "artifacts/step-1-audit.md"
```

## 2. Classify Updates

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/workflow-state.sh" step-start "$RUN_ID" 2 "Classify Updates"
```

| Category | Risk | Approach |
|----------|------|----------|
| **Patch** (1.2.3 -> 1.2.4) | Low | Update, run tests, ship |
| **Minor** (1.2.3 -> 1.3.0) | Medium | Read changelog, update, run tests |
| **Major** (1.2.3 -> 2.0.0) | High | Read migration guide, plan, test thoroughly |
| **Security fix** | Urgent | Prioritize regardless of version bump |

**Write an artifact**: `artifacts/step-2-classify.md` grouping each update by category with the planned approach.

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/workflow-state.sh" step-complete "$RUN_ID" 2 "artifacts/step-2-classify.md"
```

## 3. Update Process

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/workflow-state.sh" step-start "$RUN_ID" 3 "Update Process"
```

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

**Write an artifact**: `artifacts/step-3-update.md` listing each dependency updated, from/to versions, and test outcome per package.

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/workflow-state.sh" step-complete "$RUN_ID" 3 "artifacts/step-3-update.md"
```

## 4. Post-Update Verification

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/workflow-state.sh" step-start "$RUN_ID" 4 "Post-Update Verification"
```

- [ ] All existing tests pass
- [ ] No new type errors
- [ ] No new lint warnings
- [ ] Application starts and basic flows work

**Write an artifact**: `artifacts/step-4-verify.md` with test/type-check/lint output and smoke-test results.

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/workflow-state.sh" step-complete "$RUN_ID" 4 "artifacts/step-4-verify.md"
```

## 5. External API Version Changes

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/workflow-state.sh" step-start "$RUN_ID" 5 "External API Version Changes"
```

If an external API you depend on is deprecating a version:

- [ ] Identify which code paths are affected
- [ ] Check the API migration guide
- [ ] Update API calls (endpoints, parameters, response parsing)
- [ ] Update tests with new response shapes
- [ ] Verify the new API paths work

**Write an artifact**: `artifacts/step-5-api-changes.md` listing affected call sites and the migration steps taken (or "not applicable" if no external API change).

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/workflow-state.sh" step-complete "$RUN_ID" 5 "artifacts/step-5-api-changes.md"
```

## 6. Document

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/workflow-state.sh" step-start "$RUN_ID" 6 "Document"
```

- [ ] If an API change introduced a new constraint, add to `vault/gotchas/`
- [ ] If a major version upgrade required significant changes, add to `vault/decisions/`
- [ ] Update `vault/changelog/` with the dependency updates

**Write an artifact**: `artifacts/step-6-document.md` listing all vault entries touched (created, updated, deleted).

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/workflow-state.sh" step-complete "$RUN_ID" 6 "artifacts/step-6-document.md"
bash "${CLAUDE_PLUGIN_ROOT}/scripts/workflow-state.sh" finish "$RUN_ID" completed
```

#workflow #dependencies #update

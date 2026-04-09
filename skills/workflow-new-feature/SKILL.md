---
name: sentinel-workflow-new-feature
description: Disciplined new-feature workflow — research, plan, TDD implementation, refactor, verify, vault healing. Use whenever the user says "build", "add a feature", "implement", "create", "new component", "new page", "let's add X", "I want to build Y", or otherwise asks to create something that doesn't exist yet — even if they don't explicitly say "workflow". Enforces research-before-code, plan-before-keystroke, tests-before-implementation (RED/GREEN/REFACTOR), and automatic vault healing. Hard stop after two failed attempts to prevent context pollution. Seven steps — research, plan, write failing tests, implement, refactor, verify, document.
workflow: true
workflow-steps: 7
allowed-tools: Read Grep Glob Bash Edit Write MultiEdit TodoWrite
origin: sentinel
---

# New Feature Workflow

Step-by-step process for implementing new features. Follow every step in order.

This is a Sentinel workflow skill. When it activates, the `sentinel-workflow-runner` protocol drives execution — creates a run directory, checkpoints progress after each step, and supports resumption across sessions. You do not need to invoke the runner explicitly; it activates alongside this skill.

## Protocol summary

At the top of the workflow, create a new run:

```bash
RUN_ID=$(bash "${CLAUDE_PLUGIN_ROOT}/scripts/workflow-state.sh" start new-feature)
```

Before each numbered step, call `step-start`. After each step completes, call `step-complete` (with an artifact path if you produced one). After the final step, call `finish <run-id> completed`. On failure, call `step-fail` and follow the failure-handling rules in each section below.

Full protocol details: see `sentinel-workflow-runner` skill.

---

## 1. Research

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/workflow-state.sh" step-start "$RUN_ID" 1 "Research"
```

- [ ] Read the relevant architecture files in `vault/architecture/`
- [ ] Check `vault/decisions/` for past decisions that affect this area
- [ ] **Check `vault/investigations/` for past debugging sessions** -- learn from prior failed approaches before writing code
- [ ] Search for existing implementations that can be reused
- [ ] Identify which files will need to change

**Write an artifact**: `vault/workflows/runs/$RUN_ID/artifacts/step-1-research.md` summarizing architecture/decisions/investigation findings and the list of files that will change.

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/workflow-state.sh" step-complete "$RUN_ID" 1 "artifacts/step-1-research.md"
```

## 2. Plan

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/workflow-state.sh" step-start "$RUN_ID" 2 "Plan"
```

- [ ] Break the feature into discrete steps
- [ ] Identify dependencies between steps
- [ ] For complex features (3+ files, new patterns), use Plan Mode
- [ ] Present the plan to the user before writing code
- [ ] Identify which existing patterns to follow (check `vault/architecture/`)

**Write an artifact**: `artifacts/step-2-plan.md` with the step-by-step plan, dependencies, and patterns to follow.

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/workflow-state.sh" step-complete "$RUN_ID" 2 "artifacts/step-2-plan.md"
```

## 3. Write Tests First (RED)

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/workflow-state.sh" step-start "$RUN_ID" 3 "Write Tests First"
```

- [ ] For each component of the feature, write tests BEFORE implementation
- [ ] Follow test standards in `vault/quality/test-standards.md`
- [ ] Include: happy path, error cases, edge cases
- [ ] Run tests -- confirm they **fail** (because implementation doesn't exist yet)

**Write an artifact**: `artifacts/step-3-tests.md` listing each test file, the cases covered, and the failure output.

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/workflow-state.sh" step-complete "$RUN_ID" 3 "artifacts/step-3-tests.md"
```

## 4. Implement (GREEN)

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/workflow-state.sh" step-start "$RUN_ID" 4 "Implement"
```

- [ ] Write the minimal implementation to make tests pass
- [ ] Follow existing patterns in the codebase
- [ ] Read `vault/quality/anti-patterns.md` -- use *none* of the listed patterns
- [ ] Run tests after each component -- confirm they **pass**

### If implementation hits unexpected failures

**Do not silently try another approach.** Document what failed:

1. Create or update `vault/investigations/YYYY-MM-<brief-slug>.md`
2. Log: hypothesis, what was tried, what happened, WHY it failed
3. Each failed attempt is an entry -- append, never delete
4. Call `step-fail "$RUN_ID" 4 "<reason>"` — this records the failure in the workflow event log
5. This prevents future sessions from repeating the same dead ends

**After 2 failed attempts: STOP.** Tell the user the context may be polluted. Suggest `/clear` and a fresh start. Save the investigation file -- it persists across `/clear`. The workflow run directory also persists — on the next session, `/sentinel-workflow resume` will pick up exactly where you left off.

**Write an artifact**: `artifacts/step-4-implement.md` with the implementation summary, file paths, and final test output.

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/workflow-state.sh" step-complete "$RUN_ID" 4 "artifacts/step-4-implement.md"
```

## 5. Refactor (IMPROVE)

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/workflow-state.sh" step-start "$RUN_ID" 5 "Refactor"
```

- [ ] Clean up implementation without changing behavior
- [ ] Ensure files stay under 800 lines
- [ ] Ensure functions stay under 50 lines
- [ ] Remove any duplicate code
- [ ] Verify immutability (new objects, no mutation)

**Write an artifact**: `artifacts/step-5-refactor.md` describing what was cleaned up and confirming tests still pass.

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/workflow-state.sh" step-complete "$RUN_ID" 5 "artifacts/step-5-refactor.md"
```

## 6. Verify

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/workflow-state.sh" step-start "$RUN_ID" 6 "Verify"
```

- [ ] Read `vault/quality/gates.md` -- pass all gates
- [ ] Run the full test suite (not just new tests)
- [ ] Run linter

**Write an artifact**: `artifacts/step-6-verify.md` listing each quality gate and its pass/fail status.

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/workflow-state.sh" step-complete "$RUN_ID" 6 "artifacts/step-6-verify.md"
```

## 7. Document & Heal the Vault

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/workflow-state.sh" step-start "$RUN_ID" 7 "Document and Heal"
```

- [ ] If the feature introduces new patterns, add to `vault/decisions/`
- [ ] If any gotchas were discovered, add to `vault/gotchas/`
- [ ] If an investigation was opened, update its status to `resolved`
- [ ] **Staleness check** (see `vault/workflows/vault-maintenance.md`):
  - [ ] Are any existing gotchas now wrong because of this change?
  - [ ] Are any existing decisions now superseded?
  - [ ] Are any open investigations now resolved?
  - [ ] Delete or update stale entries -- don't leave lies in the vault
- [ ] Commit with `feat:` prefix

**Write an artifact**: `artifacts/step-7-document.md` listing all vault entries touched (created, updated, deleted).

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/workflow-state.sh" step-complete "$RUN_ID" 7 "artifacts/step-7-document.md"
bash "${CLAUDE_PLUGIN_ROOT}/scripts/workflow-state.sh" finish "$RUN_ID" completed
```

#workflow #feature

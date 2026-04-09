---
name: sentinel-workflow-refactor
description: Disciplined refactor workflow — understand, safety net, small-step refactor, verify, document. Use whenever the user says "refactor", "clean up", "restructure", "extract function", "rename", "split this file", "simplify", "DRY up", "reorganize", or otherwise asks to change code shape without changing behavior — even if they don't explicitly say "workflow". The Iron Law of this workflow is: BEHAVIOR MUST NOT CHANGE. Tests run after *every* change, not just at the end. If a bug is discovered mid-refactor, it's fixed in a separate commit. Five steps — understand, safety net, small-step refactor, verify, document.
workflow: true
workflow-steps: 5
allowed-tools: Read Grep Glob Bash Edit Write MultiEdit TodoWrite
origin: sentinel
---

# Refactor Workflow

Step-by-step process for refactoring code. The key rule: behavior must not change.

This is a Sentinel workflow skill. When it activates, the `sentinel-workflow-runner` protocol drives execution — creates a run directory, checkpoints progress after each step, and supports resumption across sessions. You do not need to invoke the runner explicitly; it activates alongside this skill.

## Protocol summary

At the top of the workflow, create a new run:

```bash
RUN_ID=$(bash "${CLAUDE_PLUGIN_ROOT}/scripts/workflow-state.sh" start refactor)
```

Before each numbered step, call `step-start`. After each step completes, call `step-complete` (with an artifact path if you produced one). After the final step, call `finish <run-id> completed`. On failure, call `step-fail` and follow the failure-handling rules in each section below.

Full protocol details: see `sentinel-workflow-runner` skill.

---

## 1. Understand Current State

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/workflow-state.sh" step-start "$RUN_ID" 1 "Understand Current State"
```

- [ ] Read the code to be refactored completely
- [ ] Read the relevant architecture files in `vault/architecture/`
- [ ] Identify what tests exist for this code
- [ ] Understand the public API (what callers depend on)

**Write an artifact**: `vault/workflows/runs/$RUN_ID/artifacts/step-1-understand.md` summarizing the code to be refactored, the existing tests, and the public API surface.

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/workflow-state.sh" step-complete "$RUN_ID" 1 "artifacts/step-1-understand.md"
```

## 2. Safety Net

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/workflow-state.sh" step-start "$RUN_ID" 2 "Safety Net"
```

- [ ] Ensure existing tests pass before starting
- [ ] If test coverage is low, write characterization tests first:
  - Tests that capture current behavior (even if the behavior seems wrong)
  - These prevent accidental behavior changes during refactoring
- [ ] Run the full test suite as baseline

```bash
# Python
pytest tests/ --cov=src/path/to/module -x -v

# TypeScript
npm test -- --coverage
```

**Write an artifact**: `artifacts/step-2-safety-net.md` with the baseline test results, coverage numbers, and any characterization tests written.

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/workflow-state.sh" step-complete "$RUN_ID" 2 "artifacts/step-2-safety-net.md"
```

## 3. Refactor in Small Steps

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/workflow-state.sh" step-start "$RUN_ID" 3 "Refactor in Small Steps"
```

- [ ] Make one change at a time
- [ ] Run tests after EACH change (not just at the end)
- [ ] If tests fail, revert the last change and try a different approach
- [ ] Common refactoring moves:
  - Extract function (large function -> smaller functions)
  - Extract module (large file -> multiple files)
  - Rename for clarity
  - Remove dead code
  - Replace conditional with polymorphism
  - Introduce parameter object (too many function args)

**Write an artifact**: `artifacts/step-3-refactor.md` listing each small step, the test result after it, and any reverts.

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/workflow-state.sh" step-complete "$RUN_ID" 3 "artifacts/step-3-refactor.md"
```

## 4. Verify

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/workflow-state.sh" step-start "$RUN_ID" 4 "Verify"
```

- [ ] All tests pass (same tests as before, same results)
- [ ] No behavior changes (the refactored code does exactly what the old code did)
- [ ] Read `vault/quality/gates.md`
- [ ] Run linter

**Write an artifact**: `artifacts/step-4-verify.md` with the full test suite output and linter output, confirming no behavior changes.

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/workflow-state.sh" step-complete "$RUN_ID" 4 "artifacts/step-4-verify.md"
```

## 5. Document

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/workflow-state.sh" step-start "$RUN_ID" 5 "Document"
```

- [ ] If the refactoring changes file structure, update `vault/architecture/`
- [ ] If the refactoring establishes a new pattern, add to `vault/decisions/`
- [ ] Commit with `refactor:` prefix

**Write an artifact**: `artifacts/step-5-document.md` listing all vault entries touched (created, updated, deleted).

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/workflow-state.sh" step-complete "$RUN_ID" 5 "artifacts/step-5-document.md"
bash "${CLAUDE_PLUGIN_ROOT}/scripts/workflow-state.sh" finish "$RUN_ID" completed
```

## What Refactoring Is NOT

- Refactoring does NOT change behavior
- Refactoring does NOT fix bugs (that's a bug fix)
- Refactoring does NOT add features (that's a feature)
- If you find a bug during refactoring, fix it in a separate commit

#workflow #refactor

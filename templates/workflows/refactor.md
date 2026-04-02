# Refactor Workflow

Step-by-step process for refactoring code. The key rule: behavior must not change.

## 1. Understand Current State

- [ ] Read the code to be refactored completely
- [ ] Read the relevant architecture files in `vault/architecture/`
- [ ] Identify what tests exist for this code
- [ ] Understand the public API (what callers depend on)

## 2. Safety Net

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

## 3. Refactor in Small Steps

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

## 4. Verify

- [ ] All tests pass (same tests as before, same results)
- [ ] No behavior changes (the refactored code does exactly what the old code did)
- [ ] Read `vault/quality/gates.md`
- [ ] Run linter

## 5. Document

- [ ] If the refactoring changes file structure, update `vault/architecture/`
- [ ] If the refactoring establishes a new pattern, add to `vault/decisions/`
- [ ] Commit with `refactor:` prefix

## What Refactoring Is NOT

- Refactoring does NOT change behavior
- Refactoring does NOT fix bugs (that's a bug fix)
- Refactoring does NOT add features (that's a feature)
- If you find a bug during refactoring, fix it in a separate commit

#workflow #refactor

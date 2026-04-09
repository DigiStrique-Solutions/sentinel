---
name: sentinel-workflow-code-review
description: Disciplined code-review workflow — self-review, general quality, language-specific checks, domain checks, then resolve. Use whenever the user says "review this", "code review", "review my changes", "check my diff", "look this over", "is this ready to commit", or asks for a second pass on code they just wrote — even if they don't explicitly say "workflow". Covers general quality, language idioms, security, design-system, and database concerns, and enforces that CRITICAL and HIGH issues are fixed before proceeding. Six steps — self-review, general review, language review, domain review, parallel execution, resolve.
workflow: true
workflow-steps: 6
allowed-tools: Read Grep Glob Bash Edit Write MultiEdit TodoWrite
origin: sentinel
---

# Code Review Workflow

Sequencing code review checks for thorough review. Run after completing implementation, before committing.

This is a Sentinel workflow skill. When it activates, the `sentinel-workflow-runner` protocol drives execution — creates a run directory, checkpoints progress after each step, and supports resumption across sessions. You do not need to invoke the runner explicitly; it activates alongside this skill.

## Protocol summary

At the top of the workflow, create a new run:

```bash
RUN_ID=$(bash "${CLAUDE_PLUGIN_ROOT}/scripts/workflow-state.sh" start code-review)
```

Before each numbered step, call `step-start`. After each step completes, call `step-complete` (with an artifact path if you produced one). After the final step, call `finish <run-id> completed`. On failure, call `step-fail` and follow the failure-handling rules in each section below.

Full protocol details: see `sentinel-workflow-runner` skill.

---

## Quick Reference

| Change type | Review focus |
|-------------|-------------|
| Python only | General quality + Python idioms |
| TypeScript only | General quality + type safety |
| Frontend UI | General quality + design system + accessibility |
| New feature (frontend) | General quality + design + UX flows |
| Auth / API / user input | General quality + security |
| Database / queries | General quality + query optimization |
| Full stack | All of the above |

## 1. Self-Review First

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/workflow-state.sh" step-start "$RUN_ID" 1 "Self-Review First"
```

- [ ] Read the full diff as if reviewing someone else's code
- [ ] Check for: unused imports, dead code, commented-out code, debug statements
- [ ] Verify no files were accidentally modified outside the intended scope
- [ ] Confirm immutability (new objects returned, not mutation)
- [ ] Read `vault/quality/anti-patterns.md` -- confirm none of the 10 patterns are present

**Write an artifact**: `vault/workflows/runs/$RUN_ID/artifacts/step-1-self-review.md` summarizing the diff scope, any suspect imports/dead code/debug statements you found, and whether the anti-pattern check passed.

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/workflow-state.sh" step-complete "$RUN_ID" 1 "artifacts/step-1-self-review.md"
```

## 2. General Code Review (always)

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/workflow-state.sh" step-start "$RUN_ID" 2 "General Code Review"
```

Review the changed files for:
- [ ] Readability and naming clarity
- [ ] Function size (<50 lines)
- [ ] File size (<800 lines)
- [ ] Error handling (no silenced errors)
- [ ] Input validation at boundaries
- [ ] No hardcoded secrets or environment-specific values

Address all CRITICAL and HIGH issues before proceeding.

**Write an artifact**: `artifacts/step-2-general-review.md` listing each finding with severity (CRITICAL/HIGH/MEDIUM/LOW) and whether it was fixed.

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/workflow-state.sh" step-complete "$RUN_ID" 2 "artifacts/step-2-general-review.md"
```

## 3. Language-Specific Review

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/workflow-state.sh" step-start "$RUN_ID" 3 "Language-Specific Review"
```

### Python changes:
- [ ] PEP 8 compliance
- [ ] Type hints on all function signatures
- [ ] Docstrings in imperative mood ("Return" not "Returns")
- [ ] Run linter: `ruff check src/` or `flake8 src/`

### TypeScript changes:
- [ ] Run type check: `tsc --noEmit`
- [ ] Run linter: `eslint src/` or `yarn lint`
- [ ] No `any` types without justification

**Write an artifact**: `artifacts/step-3-language-review.md` with linter/type-check output and any findings.

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/workflow-state.sh" step-complete "$RUN_ID" 3 "artifacts/step-3-language-review.md"
```

## 4. Domain-Specific Review

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/workflow-state.sh" step-start "$RUN_ID" 4 "Domain-Specific Review"
```

### Frontend UI changes:
- [ ] Design system tokens used (no hardcoded colors/spacing)
- [ ] Dark mode support (if applicable)
- [ ] Accessibility (aria-labels, keyboard navigation, focus management)
- [ ] All async states handled (loading, error, empty, success)
- [ ] Responsive layout

### Security-sensitive changes (auth, user input, API endpoints, tokens):
- [ ] No hardcoded secrets in diff
- [ ] Input validation present
- [ ] SQL injection prevention (parameterized queries)
- [ ] XSS prevention (sanitized HTML)
- [ ] Authentication/authorization on all endpoints

### Database / query changes:
- [ ] No N+1 queries
- [ ] Missing indexes identified
- [ ] Parameterized queries (no string interpolation)
- [ ] Migration reviewed if schema changed

**Write an artifact**: `artifacts/step-4-domain-review.md` noting which domain checklists applied and the findings from each.

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/workflow-state.sh" step-complete "$RUN_ID" 4 "artifacts/step-4-domain-review.md"
```

## 5. Parallel Execution

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/workflow-state.sh" step-start "$RUN_ID" 5 "Parallel Execution"
```

For efficiency, run independent review checks in parallel:

```
# GOOD: These have no dependencies -- run in parallel
Check 1: General code quality (read-only)
Check 2: Security scan (read-only)
Check 3: Design system compliance (read-only)

# BAD: Running these sequentially wastes time
First quality check, wait, then security check, wait, then design check
```

**Write an artifact**: `artifacts/step-5-parallel.md` noting which checks were parallelized and any findings that emerged from the batched run.

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/workflow-state.sh" step-complete "$RUN_ID" 5 "artifacts/step-5-parallel.md"
```

## 6. Resolve

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/workflow-state.sh" step-start "$RUN_ID" 6 "Resolve"
```

- [ ] All CRITICAL issues fixed
- [ ] All HIGH issues fixed
- [ ] MEDIUM issues fixed or explicitly accepted by user
- [ ] LOW issues noted for future cleanup (optional)
- [ ] Re-run tests after fixes to confirm nothing broke

**Write an artifact**: `artifacts/step-6-resolve.md` listing each issue and its resolution status, plus the final test re-run output.

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/workflow-state.sh" step-complete "$RUN_ID" 6 "artifacts/step-6-resolve.md"
bash "${CLAUDE_PLUGIN_ROOT}/scripts/workflow-state.sh" finish "$RUN_ID" completed
```

#workflow #code-review #quality

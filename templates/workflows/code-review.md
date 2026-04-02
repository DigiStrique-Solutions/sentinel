# Code Review Workflow

Sequencing code review checks for thorough review. Run after completing implementation, before committing.

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

- [ ] Read the full diff as if reviewing someone else's code
- [ ] Check for: unused imports, dead code, commented-out code, debug statements
- [ ] Verify no files were accidentally modified outside the intended scope
- [ ] Confirm immutability (new objects returned, not mutation)
- [ ] Read `vault/quality/anti-patterns.md` -- confirm none of the 10 patterns are present

## 2. General Code Review (always)

Review the changed files for:
- [ ] Readability and naming clarity
- [ ] Function size (<50 lines)
- [ ] File size (<800 lines)
- [ ] Error handling (no silenced errors)
- [ ] Input validation at boundaries
- [ ] No hardcoded secrets or environment-specific values

Address all CRITICAL and HIGH issues before proceeding.

## 3. Language-Specific Review

### Python changes:
- [ ] PEP 8 compliance
- [ ] Type hints on all function signatures
- [ ] Docstrings in imperative mood ("Return" not "Returns")
- [ ] Run linter: `ruff check src/` or `flake8 src/`

### TypeScript changes:
- [ ] Run type check: `tsc --noEmit`
- [ ] Run linter: `eslint src/` or `yarn lint`
- [ ] No `any` types without justification

## 4. Domain-Specific Review

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

## 5. Parallel Execution

For efficiency, run independent review checks in parallel:

```
# GOOD: These have no dependencies -- run in parallel
Check 1: General code quality (read-only)
Check 2: Security scan (read-only)
Check 3: Design system compliance (read-only)

# BAD: Running these sequentially wastes time
First quality check, wait, then security check, wait, then design check
```

## 6. Resolve

- [ ] All CRITICAL issues fixed
- [ ] All HIGH issues fixed
- [ ] MEDIUM issues fixed or explicitly accepted by user
- [ ] LOW issues noted for future cleanup (optional)
- [ ] Re-run tests after fixes to confirm nothing broke

#workflow #code-review #quality

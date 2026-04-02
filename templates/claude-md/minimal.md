# {{PROJECT_NAME}}

{{PROJECT_DESCRIPTION}}

## Quality Standards

Read these before declaring work complete:
- `vault/quality/anti-patterns.md` — 10 banned patterns
- `vault/quality/test-standards.md` — what constitutes a real test
- `vault/quality/gates.md` — 7 gates to pass before done

## Workflows

| Task | Read first |
|------|-----------|
| Bug fix | `vault/workflows/bug-fix.md` |

## Mandatory Behaviors

### When a fix attempt fails
- Create `vault/investigations/YYYY-MM-<slug>.md` IMMEDIATELY
- Log: hypothesis, what was tried, result, WHY it failed
- After **2 failed attempts**, STOP. Tell the user the context may be polluted. Suggest `/clear` and a fresh start with a better-scoped prompt. Do not spiral.

### When ANY test fails
- **Every failing test is YOUR responsibility.** Never dismiss a test failure as "pre-existing" or "not caused by my changes."
- Diagnose the root cause, fix the code (or the test if the test is wrong), and confirm it passes before moving on.

### Before starting in unfamiliar area
- Check `vault/investigations/` for past failed approaches
- Check `vault/gotchas/` for known pitfalls

## Critical Rules

- **Immutability:** ALWAYS create new objects, NEVER mutate existing ones
- **Error handling:** Handle explicitly at every level. Never silently swallow errors
- **Security:** No hardcoded secrets. Validate all user inputs. Parameterized queries only
- **File size:** 200-400 lines typical, 800 max. Functions under 50 lines
- **TDD:** Write ONE failing test, implement minimum to pass, refactor, repeat
- **Testing:** 80% minimum coverage
- **Git:** Conventional commits (`feat:`, `fix:`, `refactor:`). Never commit to main. Tests must pass before merge

## Testing Commands

```bash
# Customize these for your project
# Python
pytest tests/ -x -v

# TypeScript
npm test
```

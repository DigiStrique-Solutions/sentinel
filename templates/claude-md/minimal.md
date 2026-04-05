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

## Autonomy

You are an autonomous AI coding assistant. Execute commands yourself — never ask the user to run something you can run.

- **Tests, lints, builds, type checks** — Run them via Bash. Never say "you can run..."
- **File creation and edits** — Do them directly. Never say "create a file with..."
- **Git operations** — Stage, commit, branch, merge. Never say "you should commit..."
- **Package installs** — Run pip/npm/yarn. Never say "install X by running..."
- **Directory setup** — Create directories. Never say "you'll need to create..."

The ONLY things to ask about: destructive shared operations (force-push, drop DB), secrets you can't know (API keys), genuinely ambiguous intent, or paid/metered actions (deploy to prod).

## Compact Instructions

When context is compacted, preserve these critical rules:
- ALWAYS execute commands yourself — never tell the user to run something
- ALWAYS check `vault/investigations/` before attempting any fix
- ALWAYS check `vault/gotchas/` before editing files
- NEVER claim work is done without running verification commands
- After 2 failed fix attempts, STOP and tell the user to start fresh

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

# {{PROJECT_NAME}}

{{PROJECT_DESCRIPTION}}

## Quality Standards

Read these before declaring work complete:
- `vault/quality/anti-patterns.md` — 10 banned patterns
- `vault/quality/test-standards.md` — what constitutes a real test
- `vault/quality/gates.md` — 7 gates to pass before done

## Workflows — Read the Relevant One Before Starting Work

| Task | Read first |
|------|-----------|
| Bug fix | `vault/workflows/bug-fix.md` |
| New feature | `vault/workflows/new-feature.md` |
| Improve existing feature | `vault/workflows/feature-improvement.md` |
| Refactor | `vault/workflows/refactor.md` |
| New API endpoint | `vault/workflows/new-endpoint.md` |
| DB migration | `vault/workflows/database-migration.md` |
| E2E test | `vault/workflows/e2e-test.md` |
| Code review | `vault/workflows/code-review.md` |
| Performance issue | `vault/workflows/performance-investigation.md` |
| Security audit | `vault/workflows/security-audit.md` |
| Dependency update | `vault/workflows/dependency-update.md` |
| Prompt engineering | `vault/workflows/prompt-engineering.md` |
| Research / investigation | `vault/workflows/research-spike.md` |

## Compact Instructions

When context is compacted, preserve these critical rules:
- ALWAYS check `vault/investigations/` before attempting any fix — they document approaches that already failed
- ALWAYS check `vault/gotchas/` before editing files — they document non-obvious pitfalls
- NEVER skip tests. Run the full test suite after changes, not just targeted tests
- NEVER claim work is done without running verification commands (test, lint, type check)
- After 2 failed fix attempts, STOP and tell the user to start fresh
- Read `vault/quality/gates.md` before declaring work complete
- Check `vault/activity/` for recent team context

## Mandatory Behaviors

### When a fix attempt fails
- Create `vault/investigations/YYYY-MM-<slug>.md` IMMEDIATELY
- Log: hypothesis, what was tried, result, WHY it failed
- After **2 failed attempts**, STOP. Tell the user the context may be polluted. Suggest `/clear` and a fresh start with a better-scoped prompt. Do not spiral.

### After completing any task
- **Staleness check:** Scan `vault/gotchas/` and `vault/decisions/` -- delete or update anything now wrong
- See `vault/workflows/vault-maintenance.md`

### When ANY test fails
- **Every failing test is YOUR responsibility.** Never dismiss a test failure as "pre-existing" or "not caused by my changes."
- Diagnose the root cause, fix the code (or the test if the test is wrong), and confirm it passes before moving on.

### Before starting in unfamiliar area
- Check `vault/investigations/` for past failed approaches
- Check `vault/gotchas/` for known pitfalls
- Check `vault/decisions/` for architectural context

## Critical Rules

- **Immutability:** ALWAYS create new objects, NEVER mutate existing ones
- **Error handling:** Handle explicitly at every level. Never silently swallow errors
- **Security:** No hardcoded secrets. Validate all user inputs. Parameterized queries only
- **File size:** 200-400 lines typical, 800 max. Functions under 50 lines
- **TDD:** Write ONE failing test, implement minimum to pass, refactor, repeat
- **Testing:** 80% minimum coverage
- **Git:** Conventional commits (`feat:`, `fix:`, `refactor:`). Never commit to main. Tests must pass before merge

## Essential Patterns

- **Backend venv:** `<your-backend>/.venv/` -- use `.venv/bin/python`, `.venv/bin/pytest`
- **Lint (Python):** `ruff check src/` or `flake8 src/`
- **Lint (TypeScript):** `eslint src/` or `yarn lint`
- **Type check:** `mypy src/` or `yarn tsc --noEmit`

## Testing Commands

```bash
# Customize these for your project

# Python
cd <your-backend> && .venv/bin/pytest tests/ -x -v

# TypeScript
cd <your-frontend> && npm test
```

## Team Sync

This project uses shared Claude Code configuration via `.claude/shared/`.

### For new team members:
1. Install the Sentinel plugin
2. Run `/bootstrap` and select the "team" preset
3. The shared manifest at `.claude/shared/manifest.json` ensures all team members use the same plugins
4. Team-wide settings are in `.claude/shared/settings-template.json` -- merge into your `~/.claude/settings.json`

### Shared resources:
- `.claude/shared/agents/` -- Team-wide agents available to all members
- `.claude/shared/rules/` -- Team-wide rules applied to all sessions

### Contributing to shared config:
- Changes to `.claude/shared/` affect all team members
- Discuss changes before committing
- Test new agents/rules locally before adding to shared

## Reference (read on demand)

- `vault/context/service-map.md` -- ports, dependencies, dev commands
- `vault/context/db-schemas.md` -- database schema reference
- `vault/context/env-vars.md` -- environment variables by service
- `vault/architecture/` -- system design and component maps

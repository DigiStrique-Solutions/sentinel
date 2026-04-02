# Changelog

All notable changes to Sentinel will be documented in this file.

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), versioning follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.9.0] - 2026-04-02

### Added

- **Progressive disclosure for workflows** — CLAUDE.md templates no longer use `@` prefixes for vault references
  - Quality files and workflow references use backtick paths instead of `@` paths
  - Claude reads them on demand via the Read tool, only when the workflow is actually needed
  - Saves ~27K tokens of eager loading per session for projects with full workflow coverage
  - Updated all 3 CLAUDE.md templates: `minimal.md`, `standard.md`, `team.md`

- **Self-reducing session-start footprint** — Token-budgeted vault loading with priority ordering
  - Configurable token budget via `SENTINEL_TOKEN_BUDGET` env var (default: 10,000 tokens — <5% of Sonnet's 200K, <1% of Opus's 1M)
  - Priority-based loading: open investigations (highest) → relevant gotchas → session recovery → learned patterns → team activity (lowest)
  - Relevance filtering: gotchas matched against `git diff --name-only HEAD~5` to load only those relevant to recently changed code
  - Budget reporting: session-start output includes `~N tokens` usage indicator
  - Sections skipped gracefully when budget is exhausted — no silent truncation

- **Context audit command** (`/sentinel context`) — Measure and optimize total context overhead
  - Analyzes 7 context sources: CLAUDE.md (base + eager loads), global rules, project rules, MCP tool names, plugin metadata, Sentinel session-start output, vault size
  - Reports token estimates for each source as percentage of 200K context window
  - Detects `@` references that could be converted to progressive disclosure
  - Generates prioritized recommendations: high impact (>1K tokens), medium (200-1K), low (<200)
  - Identifies unused MCP servers, stale gotchas, unresolved investigations consuming budget

### Changed

- `session-start-loader.sh` — Fully rewritten with token budget system, priority-based loading, and git-diff relevance filtering
- Command count increased from 9 to 10 (added `/sentinel context`)

## [0.8.0] - 2026-04-02

### Added

- **Loop execution** (`/sentinel loop`) — Convergence loop for repetitive fix tasks
  - Repeats a task until a completion condition is mechanically verified
  - Detects stalls: stops after 2 iterations with no progress (prevents grinding through identical failures)
  - State file at `.sentinel/loop/state.json` tracks every attempt with results and summaries
  - Resumable: `/sentinel loop --resume` continues from where it left off after timeout or session restart
  - Use cases: lint cleanup, test fixes, prompt tuning, coverage improvement

- **Batch execution** (`/sentinel batch`) — Map-reduce for tasks too large for one context window
  - Discovers work items via glob pattern, processes each with isolated sub-agents
  - Each sub-agent gets its own context window — no context exhaustion on large codebases
  - State file at `.sentinel/batch/<id>/state.json` checkpoints after every item
  - Resumable: `/sentinel batch --resume` continues from last checkpoint, `--retry-failed` retries errors
  - Parallel mode: up to 5 concurrent sub-agents via `--parallel N`
  - Generates INDEX.md with results summary and per-file links
  - Use cases: codemap generation for 500K+ line repos, mass migration, bulk documentation, test stub generation

### Changed

- Command count increased from 7 to 9 (added `/sentinel loop` and `/sentinel batch`)

## [0.7.0] - 2026-04-02

### Added

- **Evidence-based verification** — Immutable audit trail of what actually happened during a session
  - `post-tool-evidence.sh` — PostToolUse hook on Bash that logs every verification command (test, lint, type check, build) with its pass/fail status to `.sentinel/sessions/<id>/evidence.log`
  - Captures: pytest, jest, vitest, playwright, ruff, eslint, tsc, yarn build, and more
  - The evidence log cannot be altered by Claude — it records what the hooks observed, not what Claude claims
  - Stop-time audit in `stop-enforcer.sh` checks evidence against what should have happened:
    - Source files modified but **no test command found** → "TESTS NEVER RAN"
    - Last test run **failed** with no subsequent pass → "TESTS FAILED"
    - Python files changed but **no linter run** → "PYTHON LINTER NEVER RAN"
    - TS/JS files changed but **no type check** → "TYPE CHECK NEVER RAN"
    - 3+ files modified but **no verification commands at all** → "NO VERIFICATION COMMANDS RUN"

- **Todo completeness enforcement** — Catches "all done!" when tasks are still pending
  - `post-tool-todo-mirror.sh` — PostToolUse hook on TodoWrite that mirrors todo state to `.sentinel/sessions/<id>/todos.json`
  - Stop-time audit checks the mirror file: if any todos are `pending` or `in_progress`, lists them with a warning
  - Solves the problem where Claude does tasks X and Y but skips task Z and claims completion

### Changed

- `stop-enforcer.sh` — Added evidence audit (section 6) and todo completeness check (section 5)
- `hooks.json` — Registered `post-tool-evidence.sh` (PostToolUse on Bash) and `post-tool-todo-mirror.sh` (PostToolUse on TodoWrite)
- Hook count increased from 17 to 19 (15 core + 4 optional)

## [0.6.0] - 2026-04-02

### Added

- **Documentation drift detection** — Automatically finds stale architecture docs at session end
  - `scripts/detect-drift.sh` — Scans `vault/architecture/` docs for file path references (`src/...`, `tests/...`, etc.) and cross-references against the actual filesystem
  - Detects dead references (files that no longer exist) and modified areas (directories with changes this session)
  - Integrated into `stop-enforcer.sh` — runs when source files were modified, outputs stale doc warnings telling Claude to update them
  - Zero config: works automatically for any project with `vault/architecture/` docs

- **CLAUDE.md fact checking** — Verifies numerical claims against actual codebase at session start
  - `scripts/check-facts.sh` — Greps CLAUDE.md for patterns like "209 connector tools", "20 controllers", etc.
  - Verifies against actual file/symbol counts (e.g., `@connector_tool` decorators, `.py` files in controllers/)
  - Warns when a claimed number differs from reality by >10%
  - Checks: connector tools (total + per platform), controllers, ORM entities, SKILL.md files, API client modules
  - Integrated into `session-start-loader.sh` — runs at session start, outputs warnings so Claude updates CLAUDE.md

### Changed

- `stop-enforcer.sh` — Calls `detect-drift.sh` when source files were modified during the session
- `session-start-loader.sh` — Calls `check-facts.sh` at session start to verify CLAUDE.md accuracy

## [0.5.0] - 2026-04-02

### Added

- **Team collaboration** — Three features for multi-developer vault sharing
  - **Vault conflict resolution** — Two-layer defense against merge conflicts
    - One-file-per-entry naming conventions enforced in all hooks (eliminates 90% of conflicts)
    - Custom git merge driver (`scripts/vault-merge-driver.sh`) concatenates both sides on conflict
    - `.gitattributes` template for vault files (`vault/**/*.md merge=sentinel-vault`)
    - Merge markers (`<!-- MERGE: review needed -->`) flag combined content for human review
  - **Team activity feed** — Daily markdown files at `vault/activity/YYYY-MM-DD.md`
    - Events logged: gotcha discovered, investigation opened/resolved, decision added, commits, branch creation, worktree merges, quality gate failures
    - Attribution via `git config user.name` — zero extra setup
    - Shared `activity-logger.sh` function sourced by all hooks
    - Session-start loader reads last 3 days of activity for team context
    - Auto-pruned: activity files >30 days archived by Tier 1 pruning
  - **Team onboarding** — Guided setup for new team members
    - `/sentinel onboard` command: reads required vault files, shows recent activity, configures settings, sets up merge driver, suggests first task, marks onboarded
    - Passive hook detection: `session-start-loader` nudges un-onboarded members with a one-line reminder each session
    - Non-Claude-Code users get plain text setup instructions

### Changed

- `post-tool-tracker.sh` — Logs vault events (gotchas, investigations, decisions) to activity feed
- `stop-git.sh` — Logs commits to activity feed
- `stop-merge.sh` — Logs worktree merges to activity feed
- `stop-enforcer.sh` — Logs quality gate warnings to activity feed
- `session-start-git.sh` — Logs branch creation to activity feed
- `session-start-loader.sh` — Loads recent team activity + checks onboarding status
- `session-start-prune.sh` — Archives activity files >30 days old (Tier 1)
- `commands/bootstrap.md` — Team preset creates activity dir, copies merge driver, configures .gitattributes
- Command count increased from 6 to 7 (added `/sentinel onboard`)

## [0.4.0] - 2026-04-02

### Added

- **Concurrent session isolation** — Auto-worktree isolation when multiple agents work on the same repo
  - `session-start-isolate.sh` — Detects concurrent Claude Code sessions in the same repo via `~/.claude/sessions/*.json` PID files
    - If concurrent session found: creates a git worktree at `.claude/worktrees/sentinel-<session-id>/`
    - Outputs instructions telling Claude to work in the isolated copy
    - Symlinks `node_modules` to avoid disk bloat
    - Copies files listed in `.worktreeinclude` (e.g., `.env` files)
    - Registers session in `.sentinel/sessions/`
  - `stop-merge.sh` — Auto-merges worktree branch back into base branch when session ends
    - Commits any remaining uncommitted changes
    - Merges worktree branch into base branch
    - For vault conflicts: keeps incoming (worktree) version (vault entries are additive)
    - Cleans up worktree directory and temporary branch
    - Cleans up session registry
  - Session-scoped `.sentinel/` namespacing — each session tracks its own modified files and scope warnings in `.sentinel/sessions/<id>/`, preventing cross-session interference

### Changed

- `session-start-git.sh` — Now worktree-aware; skips branch creation if session is already isolated in a worktree
- `post-tool-tracker.sh` — Uses session-scoped tracking directory (`.sentinel/sessions/<id>/modified-files.txt`)
- `pre-tool-scope.sh` — Uses session-scoped scope warnings (`.sentinel/sessions/<id>/scope-warned`)
- `stop-enforcer.sh` — Cleans up session-scoped data instead of nuking entire `.sentinel/` directory; safe for concurrent sessions
- Hook count increased from 15 to 17 (13 core + 4 optional)

## [0.3.0] - 2026-04-02

### Added

- **Auto-pruning** — Three-tier vault data management that keeps the vault clean automatically
  - **Tier 1 (auto-archive):** Runs every 5th session via `session-start-prune.sh`
    - Session recovery files >7 days old
    - Resolved investigations >30 days old
    - Changelog entries >90 days old
    - Superseded/deprecated decisions
    - Empty directories cleaned up
  - **Tier 2 (auto-flag):** Outputs warnings for entries needing human review
    - Gotchas where all referenced source files have been deleted
    - Open investigations older than 60 days
    - Learned patterns with 0 observations in 30+ days
  - **Tier 3 (manual):** `/sentinel prune` command for deep cleanup
    - Duplicate detection across gotchas, investigations, and decisions
    - Cross-reference validation (file paths still exist?)
    - Pattern health report (confidence scores, observation counts)
    - Vault size summary table
    - Archive cleanup (>180 day old archive entries, with user approval)
  - All pruning archives to `vault/.archive/` — never deletes
  - Archive preserves original directory structure for easy recovery

### Changed

- Hook count increased from 14 to 15 (11 core + 4 optional)
- Command count increased from 5 to 6 (added `/sentinel prune`)

## [0.2.0] - 2026-04-02

### Added

- **Git Autopilot** — Zero-knowledge git management for users who don't know (or care about) git
  - `session-start-git.sh` — Auto-creates a `sentinel/<date-time>` branch when session starts on main/master
  - `stop-git.sh` — Auto-stages, generates conventional commit messages, and commits when session ends
  - Sensitive files (`.env`, `*.pem`, `credentials.json`) are excluded from auto-commits
  - Users never need to run git commands, think about branches, or write commit messages

### Changed

- Hook count increased from 12 to 14 (10 core + 4 optional)
- `hooks.json` updated with git hooks in SessionStart and Stop lifecycle

## [0.1.0] - 2026-04-02

### Added

- Initial release
- **Vault system** — Institutional memory with investigations, gotchas, decisions, patterns, and session recovery
- **12 hooks** — 8 core (vault loader, index builder, gotcha surfacing, scope check, file tracker, test watcher, compaction save, quality enforcer) + 4 optional (pattern extractor, session summary, vault search, design check)
- **6 skills** — sentinel-methodology, quality-patterns, tdd, coding-standards, eval-harness, adversarial-eval
- **8 agents** — code-reviewer, security-reviewer, tdd-guide, architect, database-reviewer, build-resolver, refactor-cleaner, ui-reviewer
- **14 rules** — 8 common + 3 Python + 3 TypeScript
- **5 commands** — bootstrap, health, doctor, eject, config
- **3 presets** — minimal, standard, team
- **15 workflow templates** — bug-fix, new-feature, feature-improvement, refactor, new-endpoint, database-migration, e2e-test, code-review, performance-investigation, security-audit, dependency-update, prompt-engineering, research-spike, incident-response, vault-maintenance
- **3 CLAUDE.md skeletons** — minimal, standard, team
- **3 vault scripts** — build-index, update-confidence, vault-prune
- **Quality gates** — 7-gate enforcement system
- **Investigation journal protocol** — 2-failure stop rule with structured logging
- **Self-healing loop** — Staleness detection, gotcha lifecycle, pattern promotion

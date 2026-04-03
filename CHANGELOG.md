# Changelog

All notable changes to Sentinel will be documented in this file.

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), versioning follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.12.0] - 2026-04-03

### Added

- **Post-compact context reload** (`session-start-compact-reload.sh`) — When auto-compaction triggers, this hook fires on `SessionStart` with `source="compact"` and re-injects critical context:
  - Most recent session recovery file (saved by pre-compact hook moments earlier)
  - Active todo list state (task completion tracking)
  - Open investigations (highest-priority vault content)
  - Bug-fix mode flag (if active)
  - Reminder to re-read CLAUDE.md (instructions often lost during compaction)

- **Compact Instructions section** in all 3 CLAUDE.md templates — Directly controls what the Claude Code summarizer preserves during compaction. Lists the most critical rules (check investigations, check gotchas, run tests, 2-failure stop rule) that must survive context summarization.

- **Context pressure warning** (`post-tool-compact-suggest.sh`) — Tracks tool call count per session. At 80 calls (configurable via `.sentinel/config.json`), suggests manual `/compact` at a logical boundary. Manual compaction at 60-70% context preserves more detail than auto-compact at 83%. Only suggests once per session to avoid nagging.

### Changed

- Hook count increased from 21 to 23 (19 core + 4 optional)
- Test count increased from 159 to 181 (added 22 tests for compaction hooks)

## [0.11.0] - 2026-04-02

### Added

- **Effectiveness metrics** (`/sentinel stats`) — Shows whether Sentinel is actually helping, with three data sections:
  - **Vault Health**: Investigation count and resolution rate, gotcha count with churn (added/removed), decision and pattern counts
  - **Knowledge Reuse**: Gotcha surfacing count (how many times a gotcha was shown before an edit), investigation load count (how many times an investigation was loaded and led to resolution)
  - **Code Discipline**: Test/lint run rates across sessions, conventional commit breakdown, fix-to-feat ratio
  - Supports `--period 7d|30d|90d` time windows and `--json` for machine-readable output
  - Degrades gracefully: vault health always available, reuse/discipline data appears after first few sessions

- **Session stats collection** — Three hooks now track data for `/sentinel stats`:
  - `pre-tool-gotcha.sh` — Records gotcha hit count per session
  - `session-start-loader.sh` — Records which investigations were loaded at session start
  - `stop-enforcer.sh` — Aggregates session metrics into `vault/.sentinel-stats.json` before cleanup

### Changed

- Command count increased from 10 to 11 (added `/sentinel stats`)

## [0.10.0] - 2026-04-02

### Added

- **Verification gap detection** — Three-layer system to catch the #1 AI coding failure: narrow fix passes its own test but breaks adjacent functionality
  - **RED-GREEN-BREADTH check** (Stop hook) — At session end, checks the evidence log for:
    - Test scope breadth: warns when only targeted tests (e.g., `pytest test_file.py::test_one`) were run but multiple files were modified
    - Reproduce-first pattern: in bug-fix mode, warns if no failing test preceded the fix
    - Impacted test coverage: warns if tests that import modified modules were never executed
  - **Adjacent test detection** (`post-tool-impact.sh`) — When a source file is edited, greps test directories for files that import the modified module. Stores the impact list for the Stop hook to verify
  - **Bug-fix mode detection** (`prompt-bugfix-detect.sh`) — Detects bug-fix tasks from prompt keywords ("fix", "bug", "broken", "crash", "regression") or branch name (`fix/`, `bugfix/`, `hotfix/`). Enables stricter reproduce-first verification

- **BATS test suite** — 157 tests across 11 test files covering all high-risk hooks and scripts
  - Tests found and fixed 5 additional bugs during development (grep -c subshell, detect-drift output loss)
  - Uses bats-support, bats-assert, bats-file helper libraries (git submodules)
  - Test files: session-start-loader, stop-enforcer, session-start-prune, post-tool-evidence, session-start-isolate, stop-git, stop-merge, check-facts, detect-drift, post-tool-impact, prompt-bugfix-detect

### Changed

- `hooks.json` — Added `post-tool-impact.sh` (PostToolUse on Edit/Write/MultiEdit) and `prompt-bugfix-detect.sh` (Prompt)
- `stop-enforcer.sh` — Added RED-GREEN-BREADTH verification section (section 6b)
- Hook count increased from 19 to 21 (17 core + 4 optional)

## [0.9.1] - 2026-04-02

### Fixed

- **CRITICAL: session-start-index.sh nuked .sentinel/ directory** — `rm -rf .sentinel` ran after `session-start-isolate.sh` registered concurrent sessions, destroying all session data. Removed the destructive cleanup entirely; session cleanup is handled by `stop-enforcer.sh` at session end.

- **CRITICAL: Stop hook ordering prevented worktree merges** — `stop-enforcer.sh` ran before `stop-merge.sh` and deleted the session `.json` file that merge needed. Reordered to: `stop-git → stop-merge → stop-enforcer`. Also removed session `.json` deletion from enforcer (lifecycle owned by `stop-merge.sh`).

- **Subshell variable scoping in prune scripts** — `find ... | while read` created subshells where `ARCHIVED` and `ISSUES_FOUND` counter increments were lost. Both `session-start-prune.sh` (5 instances) and `scripts/vault-prune.sh` (3 instances + 1 nested) always reported 0. Fixed with process substitution (`< <(find ...)`) and here-strings (`<<< "$var"`).

- **`bc` dependency in session-start-loader.sh** — Float comparison for pattern confidence scores used `bc`, which isn't available in minimal Docker images. Replaced with portable `awk` expression.

- **Optional hooks config gap** — 4 optional hooks existed in `hooks/optional/` but weren't registered in `hooks.json`. The `/sentinel config` command saved preferences but nothing activated them. Fixed by registering all optional hooks in `hooks.json` with self-guarding config checks — each script reads `.sentinel/config.json` and exits immediately if not enabled.

- **No LICENSE file** — README said MIT but no LICENSE file existed. Added standard MIT LICENSE.

- **Git URL inconsistency** — `package.json` and README referenced `strique-io/sentinel` but actual remote is `DigiStrique-Solutions/sentinel`. Fixed both.

### Changed

- `hooks.json` — Stop hooks reordered; 4 optional hooks now registered (self-guarding)
- `commands/config.md` — Removed "must manually register hooks" note; optional hooks are pre-registered

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
  - `scripts/check-facts.sh` — Reads user-defined fact-check rules from `.sentinel/fact-checks.yml` and verifies numerical claims in CLAUDE.md against actual codebase counts
  - Configurable: each check defines a CLAUDE.md pattern to match and a shell command to count the real value
  - Warns when a claimed number differs from reality by >10%
  - No hardcoded project-specific checks — fully driven by config file
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

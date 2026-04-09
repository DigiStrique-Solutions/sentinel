# Changelog

All notable changes to Sentinel will be documented in this file.

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), versioning follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- **`/sentinel-uninstall` command** — interactive cleanup tool that reverts every project and home-directory mutation Sentinel made, so users can actually remove the plugin without leaving orphaned state behind. Before this, `claude plugin uninstall` removed the plugin files but left `vault/`, `.sentinel/`, CLAUDE.md sections, `.claude/settings.json` permission entries, `.gitattributes` merge driver lines, `git config merge.sentinel-vault.driver`, `scripts/vault-merge-driver.sh`, `.claude/shared/`, and dozens of `sentinel/*`/`autoresearch/*` branches as pollution. The new command walks the user through every category interactively with keep/delete/revert options, refuses to run against a dirty git tree, creates a mandatory backup tarball at `~/.sentinel/backups/` before any destructive action, and defaults conservatively (vault → keep, pollution → revert, ejected files → keep). Supports `--dry-run` to preview without changes, `--all` to skip prompts and apply safe defaults, and `--global` to also clean up `~/.sentinel/` plus the global vault (with an extra "type the phrase" confirmation).
  - **`commands/uninstall.md`** — user-facing command definition following the single-file markdown pattern used by `bootstrap.md`, `config.md`, and `eject.md`.
  - **`scripts/uninstall-helpers.sh`** — dispatchable bash+jq helper library (~550 lines, tested end-to-end). Discovery functions (`discover-project`, `discover-global`, `preflight-check`), backup (`create-backup`), and 13 idempotent revert functions (`revert-claude-md`, `revert-settings-json`, `revert-gitattributes`, `revert-git-config`, `delete-vault`, `delete-sentinel-state`, `delete-merge-driver-script`, `delete-shared-dir`, `delete-git-branches`, `delete-global-vault`, `revert-global-claude-settings`, `delete-plugin-data`). Every revert respects `DRY_RUN=1`, is safe to re-run, and prints `[uninstall] <what it did>` to stderr for the final summary.
  - **Precise permission removal** — instead of sourcing `configure-permissions.sh` (which has side effects and would overwrite the user's settings during discovery), the helper parses the `COMMON_PERMISSIONS`, `PYTHON_PERMISSIONS`, and `TYPESCRIPT_PERMISSIONS` bash array literals directly from the script file via awk. Round-trips exactly, no heuristics — entries the user added themselves are preserved untouched.
  - **Heuristic CLAUDE.md section removal** — detects Sentinel-added sections by known heading fingerprints (`## Quality Standards (auto-loaded)`, `## Workflows — Read Before Starting Work`, `## Mandatory Behaviors`, `## Critical Rules`, `## Essential Patterns`, `## Compact Instructions`, `## Autonomy`) and slices each section out from the heading to the next top-level heading. Works without markers, but Phase 2 will add explicit `<!-- SENTINEL:BEGIN --> / <!-- SENTINEL:END -->` markers to every mutation site for bulletproof reversion.
  - **`/sentinel-doctor --uninstall-check`** — new flag that runs the same discovery report in read-only mode, so users can preview Sentinel's footprint without starting the uninstall flow.
  - **Safety rails** — dirty-tree refusal (`git status --porcelain` must be empty), mandatory backup before any destructive action (abort entire operation if tar fails), vault deletion requires typing the exact repo name, global vault deletion requires typing `delete my global vault`, force-deleting unmerged branches requires typing `force delete branches`.

- **`/sentinel-autoresearch` command** — a generic, score-driven optimization loop with git-backed keep/discard and an append-only TSV ledger. Give it a `--task` and a `--score` shell command that prints one number, and it runs an autonomous loop: a sub-agent proposes one focused edit per iteration, the score command measures it, and the loop either commits to a run branch (`autoresearch/<run-id>`) if the score improved or does `git reset --hard HEAD` if it didn't. Every attempt — kept, discarded, or errored — is appended as a row to `.sentinel/autoresearch/<run-id>/attempts.tsv`. Two modes: `all-pass` (stop when a target value is reached) and `budget` (run until a wall-clock budget elapses, always hunting for aggregate improvements). Supports `--resume`, `--report`, and `--list`. Works for any task with one comparable number: lint cleanup, prompt tuning, test-runtime reduction, perf benchmark improvement, etc.
  - **`commands/autoresearch.md`** — the command definition, following the same single-file markdown pattern as `loop.md` and `batch.md`.
  - **`scripts/autoresearch-helpers.sh`** — dispatchable bash+jq helper library (~350 lines) handling all git, TSV, state-file, and scoring plumbing. Functions: `ar_preflight`, `ar_init_run`, `ar_run_score`, `ar_append_tsv`, `ar_commit_kept`, `ar_discard_working_tree`, `ar_update_state`, `ar_is_improvement`, `ar_list_runs`, `ar_report`. Each function is safe to call repeatedly and writes state to disk immediately so a crash mid-iteration leaves a resumable run.
  - **Never tracks `.sentinel/`** — on init, the helper appends `.sentinel/` to `.git/info/exclude` (local, uncommitted) so the TSV ledger and state files can't be accidentally committed and then wiped by a `git reset --hard` on the next discard.
  - **Per-run constraints file** — an autoresearch-style `constraints.md` (inspired by Karpathy's `program.md`) is written to each run's directory, re-read by the sub-agent each iteration. Default stub includes the simplicity criterion and rules forbidding score-command modification, test-weakening, and dependency changes.
  - **Never auto-merges** — the run branch is left intact for the user to review, merge, cherry-pick, or delete. This command only optimizes, it does not integrate.

- **`sentinel-ui-reviewer` is now DESIGN.md-aware.** The agent's first HIGH-severity review category was "Design System Compliance", but the checks were generic shape checks ("no hardcoded colors", "use the project's spacing scale", "use existing components") with no way to know what the project's actual tokens, scales, or component rules were. It could flag `#5436DA` as "hardcoded", but it couldn't say "this button should be `--color-primary-600` per your design system." Google Stitch introduced [`DESIGN.md`](https://stitch.withgoogle.com/docs/design-md/overview/) as a plain-text, LLM-readable design system document — the visual counterpart to `AGENTS.md` — and `sentinel-ui-reviewer` now treats it as a first-class input. When a project ships `DESIGN.md` at its root, the reviewer loads it as the source of truth and runs project-specific brand compliance instead of generic lint-shaped checks. When absent, it falls back cleanly to the original generic checks, so the change is additive and non-breaking.
  - **New Review Process step 1: "Discover the design system."** At the top of every review, the agent checks project root for `DESIGN.md`. If found, it reads the file in full and parses the 9-section Stitch format by section: color tokens and roles (Section 2), typography scale and hierarchy (Section 3), component stylings and states (Section 4), spacing and layout (Section 5), depth and elevation (Section 6), and do's and don'ts (Section 7). If absent, the agent notes in the summary that no design system document was found and continues with the original generic checklist.
  - **Two-mode Design System Compliance category.** The category is now split into a DESIGN.md-aware checklist (colors must match Section 2 palette *and* be used in the correct role, typography must match Section 3, spacing must come from Section 5's scale, components must match Section 4's stylings + states, depth must follow Section 6, and Section 7 do's/don'ts violations are **HIGH** severity because they are project-specific guardrails) and a generic fallback (the original 5-bullet list, unchanged) for projects without a `DESIGN.md`.
  - **Behavior verified end-to-end.** Two isolated projects, same violating component, one with a full 9-section DESIGN.md and one without. Positive case: reviewer cited Sections 2/5/6/7 by name, caught all 4 planted violations *plus* 2 bonus findings the generic mode missed (hardcoded `#FFFFFF` on button text, and a Delete button using `--color-accent` when `--color-danger` was defined for destructive actions). Fixes were prescriptive ("remove `boxShadow` — the existing border already provides depth per Section 6", "use `spacing-5` (20px) per the Card spec in Section 4") instead of hypothetical. Control case: reviewer fell through to the generic checklist cleanly, no crashes, no DESIGN.md citations. Same component, same bugs, fundamentally different review quality — the DESIGN.md-aware output is usable as a patch instruction; the fallback is usable as a lint warning.
  - **Summary format gains a `Design system source:` prefix line** above the issues table, so a "0 design-system issues" result is never ambiguous about whether the review was brand-specific or generic. Originally drafted as a table row but moved to a prefix line after observing sub-agents silently dropped the row because its shape (`DESIGN.md | generic`) didn't fit the numeric `Issues` column.
  - **No new skill, no new rule, no new hook.** `sentinel-ui-reviewer` does not reference any skill and is self-contained; the DESIGN.md logic lives inline in the agent file. `rules/` holds bootstrap-time reference docs, not runtime-loaded data. `hooks/optional/post-tool-design-check.sh` is a passive reminder and can't inject data into agent prompts. Deliberately scoped as a single-file agent enhancement.

### Design notes

Directly inspired by two pieces of prior work:
- **[karpathy/autoresearch](https://github.com/karpathy/autoresearch)** — Andrej Karpathy's experiment in autonomous ML research provided the score-driven keep/discard loop, git-based experiment tracking, the `program.md` constraints pattern, and the core insight that *one comparable number is the whole game*.
- **Strique's `/eval-loop`** — an earlier, scoped implementation of the same loop for prompt/eval runs. Lessons from production use (need for per-attempt branches, append-only ledger, ability to "keep hunting" after first pass) motivated generalizing the pattern into a reusable Sentinel command anyone can run.

Explicitly out of scope: parallel iterations, multi-metric optimization, auto-generated score commands, built-in visualization, and automatic integration with `sentinel-eval-harness` scenarios (follow-up item).

### Changed

- Command count: 11 → 12.
- README updated with the new command and a credit link to Karpathy's autoresearch.

## [0.18.0] - 2026-04-09

### Added

- **Workflows phase 2: migrated all 14 remaining templates to first-class workflow skills.** The workflow runner protocol shipped in 0.17.0 proved out on bug-fix; this release applies the same transformation mechanically to the rest of the workflow catalog. All 15 workflows are now first-class Claude Code skills with auto-activation, progressive disclosure, per-run state persistence, observability, and cross-session resumption. The linter passes cleanly on all 16 workflow skills (runner + 15 workflows).

  **New workflow skills:**
  - `sentinel-workflow-new-feature` — Research → Plan → Tests (RED) → Implementation (GREEN) → Refactor → Verify → Document
  - `sentinel-workflow-feature-improvement` — Understand current behavior → make minimal changes → verify no regression
  - `sentinel-workflow-refactor` — Behavior-preserving refactor with test safety net
  - `sentinel-workflow-code-review` — Self-review → general → language → domain → parallel execution → resolve
  - `sentinel-workflow-new-endpoint` — Full-stack endpoint addition (9 steps spanning backend entity → repository → service → controller → tests and frontend client → hook → component → route)
  - `sentinel-workflow-database-migration` — Schema change with rollback verification. **Path-scoped** to `migrations/** **/migrations/** **/*.sql db/**` so it only auto-activates in the relevant subtree.
  - `sentinel-workflow-e2e-test` — E2E authoring with Page Object Model, wait strategies, artifacts. **Path-scoped** to `**/e2e/** **/*.e2e.* **/playwright/** **/cypress/** tests/e2e/**`.
  - `sentinel-workflow-dependency-update` — Audit → classify (patch/minor/major/security) → update → verify → document
  - `sentinel-workflow-performance-investigation` — Baseline-first perf workflow. Iron Law: no optimization without before/after numbers.
  - `sentinel-workflow-security-audit` — OWASP Top 10 audit with automated scanning and findings triage
  - `sentinel-workflow-prompt-engineering` — Prompt authoring with adversarial testing and iteration
  - `sentinel-workflow-research-spike` — Time-boxed exploration with ADR output
  - `sentinel-workflow-incident-response` — Production incident workflow with severity triage and speed discipline
  - `sentinel-workflow-vault-maintenance` — Meta-workflow for vault hygiene, invoked as a sub-step by other workflows

  Each migrated workflow preserves the original template content verbatim (checkboxes, prose, decision trees, escalation gates, cross-references) and layers on the runner protocol: `workflow: true` frontmatter, explicit `workflow-state.sh` calls at every step boundary, per-step artifact writing for idempotent resumption, and softened ALL-CAPS emphasis (changed to italics per the skill-audit style guide — only domain-correct acronyms like RED/GREEN/CRITICAL/HIGH remain in caps).

  **Additive migration preserved:** `templates/workflows/` and `/sentinel-bootstrap`'s copy-to-vault behavior are unchanged. Users who already have `vault/workflows/*.md` from a previous bootstrap continue to work as before. The first-class workflow skills live alongside and auto-activate from description matches; over time, users can delete the vault copies if they prefer to rely on the plugin-shipped versions.

### Changed

- **`skill-audit` linter common-acronym allowlist expanded** with severity and priority labels (`CRITICAL`, `HIGH`, `MEDIUM`, `LOW`, `SEVERE`, `BLOCKER`, `MAJOR`, `MINOR`, `P0`–`P3`, `SEV1`–`SEV3`) and additional security terms (`SSRF`, `IDOR`, `PII`, `PHI`, `RBAC`, `ACL`, `CSP`, `HSTS`). These are domain-correct terminology for code review, security audit, and incident response workflows and were generating false BD003 positives.
- **`sentinel-workflow-performance-investigation`** `allowed-tools` upgraded from read-only (`Read Grep Glob Bash TodoWrite`) to edit-capable (`Read Grep Glob Bash Edit Write MultiEdit TodoWrite`) since step 4 actually applies fixes.
- Skill count: 11 → 25 (9 methodology + 1 workflow runner + 15 workflow skills).

## [0.17.0] - 2026-04-09

### Added

- **First-class workflows** — Sentinel workflows are now real Claude Code skills with a lightweight runner protocol, replacing (additively) the old pattern of plain markdown templates in `vault/workflows/`. Workflows gain auto-activation, scoping, progressive disclosure, state persistence, observability, and cross-session resumption without introducing a DSL or graph engine. Phase 1 ships the protocol and one canonical workflow; phase 2 will migrate the remaining 14 templates.
  - **`workflow-runner` skill** — a ~200-line protocol that any workflow skill follows. Creates per-run directories under `vault/workflows/runs/<run-id>/`, checkpoints `step_started`/`step_completed`/`step_failed`/`workflow_finished` events to `events.jsonl`, mirrors progress in human-readable `state.md`, and supports idempotent resumption via `artifacts/step-N-*.md` marker files.
  - **`workflow-bug-fix` skill** — first canonical workflow skill, migrated from `templates/workflows/bug-fix.md`. Same 6-step playbook (understand → reproduce → failing test → fix → verify → heal vault), now with `workflow: true` frontmatter, explicit `workflow-state.sh` calls at each transition, and per-step artifact writing for resumability. Preserves the Iron Law ("NO FIXES WITHOUT ROOT CAUSE INVESTIGATION FIRST") and the 2-failure-context-poisoning / 3-failure-architecture-question escalation gates.
  - **`scripts/workflow-state.sh`** — deterministic bash+jq state manager (~300 lines). Single source of truth for workflow run state. Subcommands: `start`, `step-start`, `step-complete`, `step-fail`, `finish`, `find-active`, `list`, `status`. Tested end-to-end (start → 2 steps → failure → finish → archive).
  - **`/sentinel-workflow` command** — user-facing interface for listing, inspecting, resuming, starting, and aborting workflow runs. `list` / `status [run-id]` / `resume [run-id]` / `start <workflow>` / `abort [run-id]`. Resume loads `state.md`, respects artifact markers for idempotency, and picks up from the current step.
  - **`session-start-workflow-detect.sh` hook** — new SessionStart hook that scans `vault/workflows/runs/` for in-progress runs and surfaces them in the session header with a one-line resume hint. Fails soft, never blocks session start.

### Design notes

Based on research across Anthropic's "Building Effective Agents," 8+ third-party Claude Code workflow plugins, and 7 agentic frameworks (LangGraph, Temporal, Dify, n8n, CrewAI, Inngest, AutoGen). Key findings: (1) every plugin that tried to build a declarative workflow DSL failed to ship anything users could author; the ones that shipped used markdown playbooks. (2) Anthropic's own guidance explicitly warns against framework abstractions. (3) The Inngest "named cached step" pattern translates directly: artifact files serve as idempotency markers for resumption. (4) Sentinel's existing `/sentinel-loop` and `/sentinel-batch` are already workflow primitives (loop + fan-out) — workflow steps invoke them rather than reimplementing. Full research report and design rationale in the commit that introduces this feature.

### Changed

- Skill count: 9 → 11.
- README workflow section updated with the new primitives.

## [0.16.0] - 2026-04-09

### Added

- **Global vault for cross-repo knowledge** — Sentinel now supports a personal global vault at `~/.sentinel/vault/` that loads alongside the repo vault in every session. Solves the multi-repo problem: when working across separate frontend/backend repos, knowledge that applies to both (OS quirks, tooling gotchas, personal conventions) lives in one place instead of being duplicated or lost. Read-path hooks (`session-start-loader`, `pre-tool-gotcha`, `prompt-vault-search`, `session-start-compact-reload`) load from both vaults; entries from the global vault are tagged `[global]` in session output. Write-path hooks (stop-enforcer, activity logger, session recovery) still write only to the repo vault — users explicitly promote files via `/sentinel-promote` when they become cross-cutting. New commands:
  - `/sentinel-global-init` — scaffolds `~/.sentinel/vault/`, optionally `git init`s it and adds a remote for cross-machine sync
  - `/sentinel-promote <file>` — moves a file from repo vault to global vault with git handling on both sides
  - `/sentinel-config` now exposes `vault.repo_path`, `vault.global_enabled`, `vault.global_path`
  - `/sentinel-health` reports both vaults
  - `/sentinel-bootstrap` now offers to set up the global vault if it doesn't exist
  - Shared helper `scripts/resolve-vaults.sh` provides `resolve_repo_vault`, `resolve_global_vault`, `resolve_all_vaults` functions sourced by all read-path hooks

- **Bootstrap pre-flight checks for terminal installs** — `/sentinel-bootstrap` now verifies the working directory before creating anything. Warns if the cwd is not a git repo, warns if the cwd is a subdirectory of a git repo (vault would end up in the wrong place), and confirms the final vault path with the user before proceeding. Fixes the common failure mode where users install via `claude plugin install` from their home directory, run bootstrap, and create a vault in the wrong location.

## [0.15.0] - 2026-04-09

### Added

- **`skill-audit` skill** — Static + adversarial review tool for Claude Code skills, complementing `anthropic-skills:skill-creator`. Two layers: (1) a deterministic Python linter (`scripts/lint_skill.py`) that catches frontmatter violations, line-count overflow, broken markdown links, orphan bundled files, ALL-CAPS bombing, rigid directives, time-sensitive language, Windows-style paths, missing TOCs on long reference files, and chained references — exits non-zero on errors; (2) an LLM-based `griller` subagent that runs nine adversarial review lenses against the SKILL.md (description quality, body clarity, progressive disclosure, tool/script design, anti-pattern scan, adversarial scenarios, stop conditions, skill-vs-built-in competition, the "rule of three" for script bundling). Reference docs include the full lint-rule catalog with rationale and a 20+ entry anti-pattern catalog with BAD/GOOD examples. Self-applicable: skill-audit can audit itself, including this build.
- **Auto-install `anthropic-skills` plugin** — New SessionStart hook (`scripts/ensure-skill-creator.sh`) that idempotently installs the official `anthropic-skills` plugin (which provides `skill-creator`) if it's not already present. Sentinel's `skill-audit` is designed to compose with `skill-creator`, so installing them together gives users the full skill-authoring + auditing workflow out of the box. Hook is idempotent (version-stamped marker), fails soft (never blocks session start), and falls back to a clear manual-install message if the `claude` CLI isn't available.

### Changed

- Skill count: 8 → 9.
- README install section now documents both the `anthropic-skills` auto-install and the manual fallback.

## [0.14.0] - 2026-04-09

### Added

- **`system-prompt-create` skill** — A guided workflow for authoring production-quality system prompts for AI agents. Tiered interview captures the irreducible-minimum context (objective, tools, environment, eagerness dial, guardrails, stop conditions), drafts a structured prompt against the 10-section anatomy, and runs a self-review pass against the most common 2025-2026 anti-patterns (ALL-CAPS bombing, negative-only instructions, vague language, contradictions, eagerness mismatch, tool description mush, missing escape hatches, trust-boundary confusion). Multi-file skill with reference material for prompt anatomy, battle-tested snippets (eagerness dials, reversibility-categorized guardrails, parallel tool-call patterns, anti-hallucination, context-compaction awareness), and an adversarial `griller` subagent for opt-in stress-testing of finished prompts. Synthesizes guidance from Anthropic's context-engineering and Claude 4.6 best practices, OpenAI's GPT-5 prompting guide, and patterns from leaked production system prompts. Skill count: 7 → 8.

## [0.13.1] - 2026-04-06

### Fixed

- **Auto-install `jq` dependency** — Sentinel hooks depend on `jq` for JSON parsing but never checked for it, causing cryptic "jq: command not found" errors on fresh installs. A new `ensure-deps.sh` script now runs as the first `SessionStart` hook, auto-installs `jq` via brew/apt/yum/apk if missing, and caches a version-stamped marker so it only runs once per plugin version.

- **Git Autopilot now disableable via `/sentinel-config`** — The GUIDE.md claimed Git Autopilot could be disabled via config, but the implementation didn't support it. Both `session-start-git.sh` and `stop-git.sh` now read `.sentinel/config.json` and respect the `hooks.git_autopilot` flag. The config command now exposes Git Autopilot as the first toggle option.

## [0.13.0] - 2026-04-05

### Added

- **Autonomous execution** — Three-layer system to eliminate the #1 UX complaint: Claude asking users to run commands instead of running them itself.
  - **Behavioral rule** (`rules/common/autonomy.md`) — Always-loaded rule that instructs Claude to execute commands, never suggest them. Covers tests, lints, builds, git, file operations, package installs. Clear exceptions for destructive shared ops, secrets, ambiguous intent, and paid actions.
  - **Permission auto-configuration** (`scripts/configure-permissions.sh`) — During `/sentinel-bootstrap`, detects project stack (Python, TypeScript, both) and writes `allowedTools` to `.claude/settings.json`. Pre-approves ~60-90 tool patterns covering pytest, ruff, npm, eslint, tsc, git, file operations, and more. Eliminates permission prompts that cause Claude to fall back to suggesting.
  - **CLAUDE.md autonomy section** — All 3 CLAUDE.md templates (minimal, standard, team) now include an "Autonomy" section with explicit execute-not-suggest instructions. The Compact Instructions section includes autonomy as the first rule, ensuring it survives context compaction.

### Changed

- Rule count increased from 14 to 15 (9 common + 3 Python + 3 TypeScript)
- Bootstrap command now includes Step 8b (permission auto-configuration)
- Test count increased from 181 to 200 (added 16 tests for configure-permissions + 3 for detect-drift)
- All 3 CLAUDE.md templates updated with Autonomy section and compaction-safe autonomy rule

## [0.12.1] - 2026-04-03

### Added

- **Brainstorm skill** — Structured exploration before implementation. Prevents Claude from jumping to code before understanding intent. Five phases: understand context → clarify intent (one question at a time) → propose 2-3 approaches with trade-offs → write spec → transition to execution workflow. Integrates with new-feature, feature-improvement, and refactor workflows.
- **Ghost file detection** — stop-enforcer checks files Claude claims to have written actually exist on disk. Catches the "ghost file hallucination" where Claude reports writing a file but the write never happened.

### Changed

- Skill count increased from 6 to 7 (added brainstorm)

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

- **Effectiveness metrics** (`/sentinel-stats`) — Shows whether Sentinel is actually helping, with three data sections:
  - **Vault Health**: Investigation count and resolution rate, gotcha count with churn (added/removed), decision and pattern counts
  - **Knowledge Reuse**: Gotcha surfacing count (how many times a gotcha was shown before an edit), investigation load count (how many times an investigation was loaded and led to resolution)
  - **Code Discipline**: Test/lint run rates across sessions, conventional commit breakdown, fix-to-feat ratio
  - Supports `--period 7d|30d|90d` time windows and `--json` for machine-readable output
  - Degrades gracefully: vault health always available, reuse/discipline data appears after first few sessions

- **Session stats collection** — Three hooks now track data for `/sentinel-stats`:
  - `pre-tool-gotcha.sh` — Records gotcha hit count per session
  - `session-start-loader.sh` — Records which investigations were loaded at session start
  - `stop-enforcer.sh` — Aggregates session metrics into `vault/.sentinel-stats.json` before cleanup

### Changed

- Command count increased from 10 to 11 (added `/sentinel-stats`)

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

- **Optional hooks config gap** — 4 optional hooks existed in `hooks/optional/` but weren't registered in `hooks.json`. The `/sentinel-config` command saved preferences but nothing activated them. Fixed by registering all optional hooks in `hooks.json` with self-guarding config checks — each script reads `.sentinel/config.json` and exits immediately if not enabled.

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

- **Context audit command** (`/sentinel-context`) — Measure and optimize total context overhead
  - Analyzes 7 context sources: CLAUDE.md (base + eager loads), global rules, project rules, MCP tool names, plugin metadata, Sentinel session-start output, vault size
  - Reports token estimates for each source as percentage of 200K context window
  - Detects `@` references that could be converted to progressive disclosure
  - Generates prioritized recommendations: high impact (>1K tokens), medium (200-1K), low (<200)
  - Identifies unused MCP servers, stale gotchas, unresolved investigations consuming budget

### Changed

- `session-start-loader.sh` — Fully rewritten with token budget system, priority-based loading, and git-diff relevance filtering
- Command count increased from 9 to 10 (added `/sentinel-context`)

## [0.8.0] - 2026-04-02

### Added

- **Loop execution** (`/sentinel-loop`) — Convergence loop for repetitive fix tasks
  - Repeats a task until a completion condition is mechanically verified
  - Detects stalls: stops after 2 iterations with no progress (prevents grinding through identical failures)
  - State file at `.sentinel/loop/state.json` tracks every attempt with results and summaries
  - Resumable: `/sentinel-loop --resume` continues from where it left off after timeout or session restart
  - Use cases: lint cleanup, test fixes, prompt tuning, coverage improvement

- **Batch execution** (`/sentinel-batch`) — Map-reduce for tasks too large for one context window
  - Discovers work items via glob pattern, processes each with isolated sub-agents
  - Each sub-agent gets its own context window — no context exhaustion on large codebases
  - State file at `.sentinel/batch/<id>/state.json` checkpoints after every item
  - Resumable: `/sentinel-batch --resume` continues from last checkpoint, `--retry-failed` retries errors
  - Parallel mode: up to 5 concurrent sub-agents via `--parallel N`
  - Generates INDEX.md with results summary and per-file links
  - Use cases: codemap generation for 500K+ line repos, mass migration, bulk documentation, test stub generation

### Changed

- Command count increased from 7 to 9 (added `/sentinel-loop` and `/sentinel-batch`)

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
    - `/sentinel-onboard` command: reads required vault files, shows recent activity, configures settings, sets up merge driver, suggests first task, marks onboarded
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
- Command count increased from 6 to 7 (added `/sentinel-onboard`)

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
  - **Tier 3 (manual):** `/sentinel-prune` command for deep cleanup
    - Duplicate detection across gotchas, investigations, and decisions
    - Cross-reference validation (file paths still exist?)
    - Pattern health report (confidence scores, observation counts)
    - Vault size summary table
    - Archive cleanup (>180 day old archive entries, with user approval)
  - All pruning archives to `vault/.archive/` — never deletes
  - Archive preserves original directory structure for easy recovery

### Changed

- Hook count increased from 14 to 15 (11 core + 4 optional)
- Command count increased from 5 to 6 (added `/sentinel-prune`)

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

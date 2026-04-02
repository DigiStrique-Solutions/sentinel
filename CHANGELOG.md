# Changelog

All notable changes to Sentinel will be documented in this file.

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), versioning follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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

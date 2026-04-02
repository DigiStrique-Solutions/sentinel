# Sentinel

Self-improving development methodology for Claude Code.

Sentinel is a Claude Code plugin that gives your AI assistant **institutional memory**, **quality enforcement**, and **continuous learning** — so every session builds on the last.

## What It Does

**Git Autopilot** — You never touch git. Sentinel auto-creates branches when sessions start and auto-commits when they end. No branch management, no commit messages, no git knowledge required.

**Concurrent Session Isolation** — Run multiple Claude Code agents on the same repo simultaneously. Sentinel detects concurrent sessions, auto-creates git worktrees for isolation, and auto-merges changes back when sessions end. No conflicts, no coordination needed.

**Team Collaboration** — Multiple developers share vault knowledge through git. A custom merge driver prevents conflicts on vault files. A daily activity feed logs what each team member's sessions did. New members get guided onboarding via `/sentinel onboard`.

**Verification, Not Trust** — Claude can claim "tests pass" without running them, or say "all done" with tasks still pending. Sentinel catches both. An evidence log records every test/lint/build command with its actual exit status — Claude can't retroactively claim success. A todo mirror tracks task state independently — if tasks are incomplete at session end, they're listed. The stop hook audits evidence against what should have happened: "5 Python files modified, 0 test executions found."

**Loop & Batch Execution** — Some tasks are too large for one context window. `/sentinel loop` runs a task repeatedly until a condition is met (fix all lint errors, get tests passing, tune prompts). `/sentinel batch` breaks a massive task into work items and processes each with isolated sub-agents — generate codemaps for a 500K-line repo, migrate hundreds of files, bulk-add documentation. Both track progress to disk and are resumable.

**Context Optimization** — Sentinel minimizes its own context footprint. Workflow references use progressive disclosure (loaded on demand, not eagerly). The session-start loader operates within a configurable token budget, loading vault entries in priority order and filtering gotchas by relevance to recently changed code. `/sentinel context` audits all context sources (CLAUDE.md, rules, MCP servers, plugins, hooks, vault) with token estimates and actionable recommendations.

**Documentation Drift Detection** — Architecture docs and CLAUDE.md go stale as code changes. Sentinel detects this automatically. At session end, it scans architecture docs for dead file references. At session start, it verifies CLAUDE.md numerical claims against actual counts. Stale docs get flagged so Claude updates them.

**Memory** — A vault system that persists investigations, gotchas, decisions, and patterns across sessions. When a fix attempt fails, it's logged. When a non-obvious constraint is discovered, it's recorded. The next session reads these before starting work.

**Discipline** — Hooks that enforce quality gates, TDD workflow, and code review standards automatically. A stop hook verifies all gates pass before work is declared complete. Pre-tool hooks surface relevant gotchas before you repeat a known mistake.

**Growth** — Pattern extraction that identifies recurring solutions and promotes them to reusable knowledge. Stale vault entries are flagged and cleaned. The system gets smarter over time.

## Install

```bash
claude plugin add sentinel
```

Then bootstrap your project:

```
/sentinel bootstrap
```

This scaffolds a `vault/` directory, quality gates, and workflows tailored to your project. Choose a preset:

| Preset | What You Get | Best For |
|--------|-------------|----------|
| **minimal** | Vault skeleton + bug-fix workflow + quality gates | Trying Sentinel |
| **standard** | Full vault + 13 workflows + quality gates + CLAUDE.md | Solo developers |
| **team** | Standard + shared sync + team onboarding | Teams |

## Core Concepts

### The Vault

A directory of markdown files that serves as institutional memory:

```
vault/
├── investigations/     # Debug journals (hypothesis → attempt → result)
├── gotchas/           # Non-obvious constraints ("this looks right but fails because...")
├── decisions/         # Architecture Decision Records (ADRs)
├── workflows/         # Step-by-step processes for common tasks
├── patterns/learned/  # Extracted patterns from successful solutions
├── quality/           # Anti-patterns, test standards, quality gates
├── architecture/      # System design docs
├── changelog/         # What changed and when
└── session-recovery/  # Context saved before compaction
```

### Investigation Journal Protocol

When a fix attempt fails:

1. Create `vault/investigations/YYYY-MM-<slug>.md`
2. Log: hypothesis, what was tried, what happened, WHY it failed
3. After **2 failed attempts** — STOP. Context is polluted. Start fresh.
4. The next session reads this file and skips the dead ends.

### Quality Gates

7 sequential gates enforced before work is declared complete:

1. **Tests pass** — All existing + new tests green
2. **No anti-patterns** — None of the 10 banned patterns present
3. **Correct, not safe** — Actual fix, not a workaround
4. **Architecture alignment** — Follows existing patterns
5. **Completeness** — Error handling, validation, logging
6. **Self-review** — Read the diff as a reviewer
7. **Vault maintenance** — Stale entries updated/removed

### Self-Healing Loop

```
Session starts → hooks load vault context
  → gotchas surface before mistakes repeat
  → investigations prevent dead-end approaches
  → quality gates enforce standards at session end
  → patterns extracted from successful work
  → vault updated with new knowledge
Next session starts → better context loaded
```

## What's Included

### Hooks (19)

**Core (15):**
- `session-start-isolate` — Detects concurrent sessions, auto-creates worktrees for isolation
- `session-start-git` — Auto-creates branch if on main/master (Git Autopilot)
- `session-start-loader` — Loads vault context (investigations, gotchas, recovery)
- `session-start-index` — Builds searchable vault index
- `session-start-prune` — Auto-archives stale vault entries every 5th session
- `pre-tool-gotcha` — Surfaces relevant gotchas before tool execution
- `pre-tool-scope` — Validates file edits stay within task scope
- `post-tool-tracker` — Tracks files modified during session (session-scoped)
- `post-tool-test-watch` — Reminds to run tests after code changes
- `post-tool-evidence` — Logs verification commands (test/lint/build) with pass/fail status
- `post-tool-todo-mirror` — Mirrors TodoWrite state for independent completeness checking
- `pre-compact-save` — Saves session context before compaction
- `stop-enforcer` — Enforces quality gates at session end (session-scoped cleanup)
- `stop-git` — Auto-commits all changes with conventional message (Git Autopilot)
- `stop-merge` — Auto-merges worktree branch back and cleans up

**Optional (4, self-guarding — enable via `/sentinel config`):**
- `stop-pattern-extractor` — Extracts reusable patterns from session
- `stop-session-summary` — Generates session summary for vault
- `prompt-vault-search` — Searches vault for relevant context on user prompts
- `post-tool-design-check` — Reminds to run design review after frontend edits

### Skills (6)

- `sentinel-methodology` — Core methodology (investigations, self-healing, gates)
- `quality-patterns` — Anti-patterns and test standards
- `tdd` — Test-driven development enforcement
- `coding-standards` — Style and quality rules
- `eval-harness` — AI prompt/agent evaluation framework
- `adversarial-eval` — Convergence protocol for finding flaws

### Agents (8)

- `code-reviewer` — General code quality review
- `security-reviewer` — OWASP Top 10 scanning
- `tdd-guide` — TDD cycle enforcement
- `architect` — System design advisor
- `database-reviewer` — SQL/schema optimization
- `build-resolver` — Build error diagnosis and fix
- `refactor-cleaner` — Dead code removal
- `ui-reviewer` — Frontend design/UX/a11y review

### Rules (14)

Common rules (8) plus language-specific extensions for Python (3) and TypeScript (3).

### Commands (10)

- `/sentinel bootstrap` — Scaffold vault and workflows for a new project
- `/sentinel health` — Dashboard showing vault health metrics
- `/sentinel doctor` — Diagnose and fix common setup issues
- `/sentinel prune` — Deep vault cleanup (duplicates, dead refs, archive management)
- `/sentinel eject` — Export all Sentinel content to standalone files
- `/sentinel config` — View and modify Sentinel settings
- `/sentinel onboard` — Guided team onboarding for new members
- `/sentinel loop` — Convergence loop: repeat a task until a condition is met (lint cleanup, test fixes, prompt tuning)
- `/sentinel batch` — Map-reduce: break a huge task into work items, process each with sub-agents (codemap generation, mass migration, bulk docs)
- `/sentinel context` — Audit all context sources with token estimates and optimization recommendations

### Workflows (13)

Step-by-step processes for: bug fix, new feature, feature improvement, refactor, new endpoint, database migration, E2E testing, code review, performance investigation, security audit, dependency update, prompt engineering, and research spikes.

## How It Works

Sentinel splits content into two categories:

**Plugin-owned (auto-updates):** Hooks, skills, agents, rules, commands, templates. These ship with the plugin and update when you update Sentinel.

**Project-owned (your content):** The `vault/` directory, your `CLAUDE.md`, and any customizations. These are scaffolded by `/sentinel bootstrap` and belong to your project. Sentinel never overwrites them.

## Configuration

After bootstrapping, customize via `/sentinel config`:

```
/sentinel config set hooks.optional.design-check enabled
/sentinel config set hooks.optional.pattern-extractor enabled
```

Or edit the generated `.sentinel.json` in your project root.

## Philosophy

1. **Memory beats intelligence.** A mediocre solution that's remembered is better than a brilliant one that's forgotten.
2. **Two failures, then stop.** After two failed fix attempts, the context is polluted. Start fresh with the investigation journal.
3. **Tests are truth.** Self-assessment is unreliable. Verification commands are the source of truth.
4. **Heal the vault.** Every session should leave the vault more accurate than it found it.
5. **Ship, then improve.** Don't design for hypothetical futures. Build what's needed now.

## Changelog

See [CHANGELOG.md](CHANGELOG.md) for version history.

## Contributing

```bash
git clone https://github.com/DigiStrique-Solutions/sentinel.git
cd sentinel
# Make changes, validate with: claude plugin validate .
```

## License

MIT

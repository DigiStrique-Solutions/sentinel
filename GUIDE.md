# Sentinel User Guide

Sentinel is a Claude Code plugin that gives your AI coding assistant a memory, discipline, and the ability to verify its own work. Without it, every Claude Code session starts from zero — no knowledge of what happened before, no accountability for what it claims, and no protection against repeating the same mistakes. Sentinel fixes all of that.

## Getting Started

Install Sentinel and set up your project in under a minute:

```
claude plugin add sentinel@strique-marketplace
```

Then bootstrap your project:

```
/sentinel bootstrap
```

You'll be asked to choose a preset:

```
Choose a preset:

  minimal   — Vault + bug-fix workflow + quality gates. Best for trying Sentinel.
  standard  — Full vault + 13 workflows + quality gates. Best for solo developers.
  team      — Standard + team sync + onboarding. Best for teams.

Select: standard
```

That's it. Sentinel is now active. Every session from here on out benefits from institutional memory, quality enforcement, and verification.

---

## The Problems Sentinel Solves

### 1. Claude forgets everything between sessions

**The problem:** You spent an hour debugging an auth issue. Claude found that the redirect was failing because of a race condition in the session middleware. You fixed it. Next day, a related bug comes up. Claude has no memory of yesterday's session — it tries the same three approaches you already ruled out, wastes 20 minutes, and eventually rediscovers what you already knew.

**What Sentinel does:** It maintains a vault — a directory of markdown files that persists across sessions. When Claude discovers something non-obvious (a gotcha), debugs a tricky issue (an investigation), or makes an architectural decision, it's saved to the vault. The next session loads this context automatically.

**What you see:**

When a session starts:
```
VAULT CONTEXT LOADED (2 investigations, 5 gotchas, ~1,400 tokens):

OPEN INVESTIGATIONS (check before attempting fixes)
- 2026-04-03-auth-redirect.md: Race condition in session middleware

KNOWN GOTCHAS (pitfalls to avoid)
- timezone-handling: Always use ISO 8601 — relative timestamps break with DST
- meta-oauth-localhost: Meta Ads OAuth doesn't allow localhost redirect URIs
```

Claude now knows what was tried before, what didn't work, and why. It skips the dead ends and goes straight to the right approach.

---

### 2. Claude loses everything mid-session when context compacts

**The problem:** You're 45 minutes into a session. Claude has been following your CLAUDE.md rules perfectly — using the right patterns, avoiding anti-patterns, following your workflow. Then auto-compaction triggers. Suddenly Claude ignores your rules, uses patterns you banned, and forgets everything it was working on. Your project instructions were followed 100% before compaction and violated 100% after. This is the #2 most reported Claude Code issue.

**What Sentinel does:** Three layers of compaction defense:

1. **Before compaction** — A pre-compact hook saves the current session state (files modified, task description, todo list, open investigations) to a recovery file on disk.

2. **During compaction** — A "Compact Instructions" section in your CLAUDE.md tells the summarizer which rules to preserve. This directly controls what survives the summary — check investigations before fixes, check gotchas before edits, never skip tests, 2-failure stop rule.

3. **After compaction** — A post-compact reload hook fires immediately and re-injects the recovery file, active todo list, open investigations, and bugfix mode flag. It also reminds Claude to re-read CLAUDE.md.

Additionally, a context pressure warning suggests manual `/compact` at 80 tool calls (configurable). Manual compaction at a logical boundary preserves more detail than auto-compact at 83% capacity.

**What you see:**

Before compaction:
```
PRE-COMPACT: Session context saved to vault/session-recovery/2026-04-03T14-30-00.md
```

After compaction fires:
```
COMPACTION DETECTED — Reloading critical context:

POST-COMPACTION CONTEXT RECOVERY
  Task: Fixing auth redirect loop
  Files: src/auth/login.py, src/auth/session.py, tests/auth/test_login.py

ACTIVE TASK LIST (from before compaction)
  - [completed] Reproduce the bug with failing test
  - [completed] Fix the redirect loop
  - [pending] Write integration tests
  Resume from the first incomplete task.

OPEN INVESTIGATIONS (still active)
  - 2026-04-03-auth-redirect.md
  Check these before attempting fixes.

IMPORTANT: Re-read CLAUDE.md for project rules. Compaction may have lost instructions.
```

Earlier in the session, before auto-compact triggers:
```
CONTEXT PRESSURE: 80 tool calls this session. Consider running /compact at a
logical boundary to preserve context quality.
```

The vault knowledge (gotchas, investigations, decisions) is never lost because it's on disk, not in the context window.

---

### 3. Claude says "done" but tests never actually ran

**The problem:** You ask Claude to fix a bug. It modifies three files, writes a test, and says "All tests pass, the fix is complete." You trust it and move on. Later, you discover the tests were never actually executed — Claude just wrote them and assumed they'd pass. Or worse, it ran the tests but they failed, and Claude claimed success anyway.

**What Sentinel does:** An evidence log records every test, lint, and build command with its actual pass/fail result. Claude can't retroactively claim success. At session end, Sentinel audits the evidence against what should have happened.

**What you see:**

If Claude modified 5 Python files but never ran pytest:
```
VAULT MAINTENANCE CHECKLIST:

- [ ] TESTS NEVER RAN — 5 file(s) modified but no test command found in evidence log.
- [ ] PYTHON LINTER NEVER RAN — 5 Python file(s) modified but no ruff/pylint found in evidence log.
```

If Claude ran tests but the last run failed:
```
- [ ] TESTS FAILED — Last test run at 14:32:15 ended with failure. No subsequent passing run found.
```

If Claude used TodoWrite to plan 5 tasks but only completed 3:
```
INCOMPLETE TASKS — 2 task(s) not marked as completed:
    - [pending] Write integration tests
    - [in_progress] Update API documentation
```

The evidence is captured by hooks that observe actual command execution — not what Claude says happened, but what the hooks saw happen.

---

### 4. Claude fixes the symptom but breaks adjacent code

**The problem:** You report a bug in the login flow. Claude fixes it and writes a test for the exact scenario you described. The test passes. You open the browser, try logging in — it works. Then you try logging out and the app crashes. Claude fixed the narrow symptom but never checked whether the fix broke anything nearby.

**What Sentinel does:** Three layers of verification gap detection:

1. **Test scope check** — If Claude modified 5 files but only ran one targeted test (`pytest test_login.py::test_specific_fix`), Sentinel warns that the scope is too narrow.

2. **Adjacent test detection** — When a source file is edited, Sentinel finds all test files that import that module. At session end, it checks whether those tests were actually run.

3. **Bug-fix mode** — When the task looks like a bug fix (you said "fix", "bug", "broken", or the branch is `fix/`), Sentinel enforces reproduce-first: there should be a failing test before the fix, not just a passing test after.

**What you see:**

```
- [ ] NARROW TEST SCOPE — Only targeted tests were run. Consider running the full
      test suite to catch regressions in adjacent code.

- [ ] IMPACTED TESTS NOT RUN — These test files import modified code but were not executed:
    - tests/test_session.py
    - tests/test_logout.py

- [ ] NO REPRODUCE STEP — This appears to be a bug fix, but no failing test was
      recorded before the fix. Reproduce the bug with a failing test first.
```

---

### 5. Claude writes tests that test the mock, not the code

**The problem:** You ask Claude to add tests for a service. It creates a test file, mocks the service, and asserts the mock was called. The test passes — but it would pass even if you deleted the entire service. The test is testing the mock setup, not the actual code. This is the most common test quality failure in AI-generated code.

**What Sentinel does:** Quality gates and anti-patterns documentation explicitly ban this pattern. The stop hook checks for test execution and warns when tests exist but may not exercise real code. The verification gap detection warns when test scope is too narrow relative to the changes made.

**What you see:**

The anti-patterns file loaded into Claude's context includes:
```
ANTI-PATTERN #1: Testing the Mock, Not the Code

BAD — test mocks the function under test:
  classifier = MagicMock()
  classifier.classify.return_value = result
  assert result.needs_planning is True
  # This passes even if ComplexityClassifier is deleted.

GOOD — test calls the real function:
  classifier = ComplexityClassifier()
  result = await classifier.classify("Audit my campaigns")
  assert result.needs_planning is True
```

Claude sees this before writing tests and avoids the pattern. If it still writes a narrow test, the verification gap detection catches it at session end.

---

### 6. Claude tries a fix that already failed last week

**The problem:** A bug keeps resurfacing. Each time, Claude tries the same obvious approach, hits the same wall, and wastes 30 minutes before discovering the approach doesn't work. There's no record of past debugging sessions.

**What Sentinel does:** The investigation journal protocol requires logging every failed approach immediately — what was tried, what happened, and why it failed. Investigations are loaded at session start with the highest priority, so Claude sees them before it starts working.

After 2 failed attempts in a single session, Sentinel enforces a hard stop: the context is likely polluted with failed reasoning, and a fresh session with the investigation file is faster than a 5th attempt.

**What you see:**

When Claude hits a failure:
```
Investigation logged: vault/investigations/2026-04-03-auth-redirect.md
  Attempt 1: Tried reordering middleware. Failed because session is initialized after redirect.
```

After a second failure:
```
Two approaches failed on this issue. Context may be polluted.
Suggestion: /clear and restart with a better-scoped prompt.
The investigation file persists across /clear — the next session will see it.
```

Next session starts:
```
OPEN INVESTIGATIONS (check before attempting fixes)
- 2026-04-03-auth-redirect.md:
    Attempt 1: Middleware reordering — failed (session not initialized)
    Attempt 2: Session initialization in redirect handler — failed (circular dependency)
```

Claude skips both dead ends and tries something different.

When an investigation is resolved, Sentinel automatically moves it to `vault/investigations/resolved/` at session end. After 30 days, resolved investigations are archived. The vault cleans itself.

---

### 7. Claude gets stuck in a loop, wasting hundreds of API calls

**The problem:** Claude tries to fix a build error. The fix introduces a new error. Claude fixes that, which reintroduces the first error. This cycles for 50+ iterations, burning through your API quota while making zero progress. The leaked Claude Code source data showed sessions with up to 3,272 consecutive failures — globally, ~250,000 API calls per day were wasted on these spirals.

**What Sentinel does:** Two mechanisms:

1. **Investigation journal's 2-failure stop rule** — After 2 failed approaches to the same problem, Sentinel forces a stop. The context is polluted with failed reasoning, and continuing will spiral. A fresh session with the investigation file is faster.

2. **Loop command's stall detection** — When using `/sentinel loop`, if 2 consecutive iterations make no progress (same number of items remaining), the loop stops automatically instead of grinding through identical failures.

**What you see:**

After the second failure:
```
Two approaches failed on this issue. Context may be polluted.
Suggestion: /clear and restart with a better-scoped prompt.
Investigation saved: vault/investigations/2026-04-03-build-error.md
```

During a loop:
```
--- Loop iteration 7/20 ---
Items remaining: 3

--- Loop iteration 8/20 ---
Items remaining: 3

Loop STUCK — no progress for 2 iterations.
This usually means the remaining issues require a different approach.
```

No more burning through your API quota on the same error 50 times.

---

### 8. Multiple agents editing the same repo cause conflicts

**The problem:** You're running two Claude Code sessions on the same repo — one working on the frontend, another on the backend. They both edit shared config files. When you try to commit, there are merge conflicts everywhere.

**What Sentinel does:** At session start, Sentinel checks for other active Claude Code sessions in the same repo. If it finds one, it automatically creates a git worktree — an isolated copy of the repo where the second session works independently. When the session ends, changes are automatically merged back.

**What you see:**

Session 1 starts normally:
```
SENTINEL: Session registered. No concurrent sessions detected.
```

Session 2 starts while Session 1 is still active:
```
CONCURRENT SESSION DETECTED: 1 other session(s) active in this repo.
AUTO-ISOLATED: Created worktree at .claude/worktrees/sentinel-abc123/

IMPORTANT — You MUST work in the isolated copy:
  Working directory: .claude/worktrees/sentinel-abc123/
  Branch: worktree-sentinel-abc123
  Changes will be auto-merged back when this session ends.
```

When Session 2 ends:
```
SENTINEL: Merged 3 commit(s) from worktree into 'main'.
```

No manual merge conflicts. No coordination needed. You just start sessions and work.

---

### 9. Git is overwhelming

**The problem:** You're a data scientist, a designer, or a student. You don't know git. You don't want to learn git. You just want to write code and have it saved properly.

**What Sentinel does:** Git Autopilot handles everything. When a session starts, Sentinel creates a dedicated branch (so you never accidentally commit to main). When it ends, Sentinel stages your changes, generates a commit message from the files you modified, and commits. Sensitive files are automatically excluded — `.env`, `*.pem`, `*.key`, `credentials.json`, and `secrets.*` are never staged, even if Claude created or modified them. This also prevents the reported issue of Claude accidentally committing sensitive files when switching branches.

**What you see:**

Session starts:
```
GIT AUTOPILOT: Working on branch 'sentinel/2026-04-03-14-22-31'.
```

Session ends:
```
GIT AUTOPILOT: Committed 7 file(s) to 'sentinel/2026-04-03-14-22-31'
  — feat: update src, tests (7 files)
```

You never run `git add`, `git commit`, `git push`, or write a commit message. It just works.

---

### 10. The task is too large for one context window

**The problem:** You need to generate documentation for a 500,000-line codebase, or migrate 200 files from one pattern to another, or add type annotations to every function in the project. Claude runs out of context after processing 20 files and the other 180 are untouched.

**What Sentinel does:** Two commands for large tasks:

**`/sentinel batch`** breaks a massive task into independent work items. Each item is processed by a sub-agent with its own context window. Progress is checkpointed after every item, so if the session crashes, you resume from the last checkpoint — not from the beginning.

**`/sentinel loop`** repeats a task until a completion condition is mechanically verified. It detects stalls — if two consecutive iterations make no progress, it stops instead of grinding through identical failures.

**What you see:**

For batch processing:
```
/sentinel batch "generate documentation" --target "src/**/*.py" --parallel 3

Batch created: 150 files to process.

--- Processing src/auth/login.py (1/150) ---
--- Processing src/auth/session.py (2/150) ---
--- Processing src/auth/permissions.py (3/150) ---

Progress: 50/150 done, 0 failed, 100 remaining

...

COMPLETED. Processed 150/150 files.
Output: .sentinel/batch/batch-abc123/results/INDEX.md
```

If it crashes at file 73:
```
/sentinel batch --resume

Resuming batch-abc123 from item 74/150 (73 completed, 0 failed)
```

For convergence loops:
```
/sentinel loop "run ruff check src/ and fix all errors" --until "ruff reports 0 errors" --max 20

--- Loop iteration 1/20 ---
Running ruff... 47 errors found. Fixing...

--- Loop iteration 2/20 ---
Running ruff... 23 errors found. Fixing...

--- Loop iteration 5/20 ---
Running ruff... 0 errors found.

Loop COMPLETED after 5 iterations.
Condition met: ruff reports 0 errors
```

If it gets stuck:
```
--- Loop iteration 7/20 ---
Items remaining: 3

--- Loop iteration 8/20 ---
Items remaining: 3

Loop STUCK — no progress for 2 iterations.
Items remaining: 3
This usually means the remaining issues require a different approach.
```

---

### 11. The context window fills up with irrelevant content

**The problem:** You have CLAUDE.md, rules, MCP servers, plugins, and vault content all competing for space in the context window. Most of it is irrelevant to the current task. A workflow you'll never use this session takes 3,000 tokens. MCP tool names you'll never invoke take another 500.

**What Sentinel does:** Two strategies:

**Progressive disclosure** — Workflows aren't loaded into context at session start. They're referenced by path in CLAUDE.md, and Claude reads them on demand only when the task matches. This saves ~27,000 tokens for projects with full workflow coverage.

**Token-budgeted loading** — The session-start loader operates within a configurable budget (default: 10,000 tokens). It loads vault content in priority order: open investigations first (highest value), then gotchas relevant to recently changed code, then session recovery, then patterns, then team activity. When the budget is exhausted, lower-priority sections are skipped gracefully.

**What you see:**

Session start shows what was loaded and how much budget was used:
```
VAULT CONTEXT LOADED (2 investigations, 5 gotchas, ~1,400 tokens):
  ...
```

To see the full breakdown, run `/sentinel context`:
```
TOTAL CONTEXT OVERHEAD (before you type anything)
Source                      Tokens     % of 200K window
CLAUDE.md (base)            1,900      0.9%
Rules                       800        0.4%
MCP tool names              272        0.1%
Sentinel session-start      1,400      0.7%
────────────────────────────────────────────
TOTAL                       4,372      2.2%
Remaining for work:         195,628    97.8%

Recommendations:
  HIGH IMPACT: Resolve 2 open investigations (save 400 tokens)
  MEDIUM: Prune 3 stale gotchas (save 200 tokens)
```

---

### 12. Documentation goes stale without anyone noticing

**The problem:** Your architecture docs reference `src/models/User.py`, but that file was renamed to `src/entities/user.py` three months ago. Your CLAUDE.md says "209 connector tools" but the actual count is now 215. Nobody noticed because nobody checks.

**What Sentinel does:** Two automatic checks:

**Drift detection** — At session end, when source files were modified, Sentinel scans architecture docs for file path references and checks if those files still exist. Dead references are flagged.

**Fact checking** — At session start, Sentinel verifies numerical claims in CLAUDE.md against actual file counts (configurable via `.sentinel/fact-checks.yml`). If the claim says 209 but the real count is 215, it warns.

**What you see:**

At session end:
```
DOCUMENTATION DRIFT DETECTED:
  - vault/architecture/database.md:
    Dead references:
      - src/models/User.py no longer exists
    Modified areas:
      - src/entities/ had files modified this session
  - [ ] Update the stale architecture docs listed above.
```

At session start:
```
CLAUDE.md FACT CHECK — numbers may be outdated:
  - Connector tools: CLAUDE.md says 209, actual is 215
  Update CLAUDE.md with current counts.
```

---

### 13. Team members don't share knowledge

**The problem:** Sarah debugged a tricky timezone issue on Monday and discovered a non-obvious constraint. Mike hits the same issue on Wednesday in a different part of the codebase. He spends an hour debugging before stumbling on the same solution Sarah already found.

**What Sentinel does:** The vault is a shared directory committed to git. When Sarah discovers a gotcha, it's saved to `vault/gotchas/timezone-handling.md`. When Mike starts a session, Sentinel loads that gotcha into his context — before he touches any code. A daily activity feed at `vault/activity/` shows what each team member's sessions did.

A custom git merge driver prevents conflicts on vault files. New members get guided onboarding via `/sentinel onboard`.

**What you see:**

Sarah's session:
```
Gotcha saved: vault/gotchas/timezone-handling.md
  Always use ISO 8601 — relative timestamps break with DST transitions.
```

Mike's session (two days later, different area of code):
```
GOTCHA ALERT for DatePicker.tsx — review before editing:
- timezone-handling: Always use ISO 8601 — relative timestamps break with DST
  (read vault/gotchas/timezone-handling.md)
```

Mike avoids the bug entirely. He never even knows he was about to make a mistake.

New team member joins:
```
/sentinel onboard

Welcome! Here's what the team has been working on:

RECENT ACTIVITY (last 3 days)
  2026-04-03 — sarah: discovered gotcha: timezone-handling
  2026-04-02 — mike: resolved investigation: auth-redirect
  2026-04-01 — team: 12 commits, all tests passed

YOUR FIRST TASK
  Read vault/workflows/bug-fix.md for the team's bug-fix protocol.

Onboarding complete!
```

---

## Commands Reference

| Command | What it does |
|---------|-------------|
| `/sentinel bootstrap` | Set up Sentinel for a new project (run once) |
| `/sentinel health` | Show vault health, open investigations, staleness warnings |
| `/sentinel doctor` | Diagnose and fix common setup issues |
| `/sentinel stats` | Show effectiveness metrics: vault health, knowledge reuse, code discipline |
| `/sentinel context` | Audit context window usage with token estimates and recommendations |
| `/sentinel config` | Enable/disable optional hooks and adjust thresholds |
| `/sentinel prune` | Deep vault cleanup: duplicates, dead references, archive management |
| `/sentinel loop` | Repeat a task until a condition is met (lint cleanup, test fixes) |
| `/sentinel batch` | Break a massive task into work items with sub-agents (bulk docs, migrations) |
| `/sentinel onboard` | Guided setup for new team members |
| `/sentinel eject` | Copy all plugin files into your project for full customization |

---

## How It Works Under the Hood

Sentinel is built on Claude Code's hook system — shell scripts that run at specific points in the session lifecycle:

**When a session starts:** Load vault context (investigations, gotchas), check for concurrent sessions, create a git branch, verify CLAUDE.md facts, rebuild the vault index if stale.

**Before a tool runs:** Surface relevant gotchas for the file being edited. Check if the edit is within the task scope.

**After a tool runs:** Track modified files. Log verification commands (test, lint, build) with pass/fail status. Detect test files impacted by source changes. Mirror todo state for completeness checking.

**When a session ends:** Enforce quality gates. Audit the evidence log. Check for incomplete todos. Auto-move resolved investigations. Collect session stats. Auto-commit changes. Merge worktree branches back.

Everything is a shell script. No server, no database, no external dependencies beyond bash, jq, and git. The vault is plain markdown files committed to your repo. You can read, edit, or delete any of it.

---

## FAQ

**Does Sentinel slow down my sessions?**
No. Session-start hooks run in parallel and complete in under 2 seconds. Per-tool hooks run in under 100ms. Stop hooks run after your work is done. The token budget keeps context loading lean.

**Does Sentinel work with any language?**
The core features (vault, investigations, git autopilot, concurrent isolation, batch/loop) are language-agnostic. The verification hooks (test detection, lint checking) currently support Python and TypeScript/JavaScript, with detection for Go, Rust, and others.

**Can I use Sentinel without the git features?**
Yes. Git Autopilot and concurrent isolation are separate hooks. You can disable them via `/sentinel config` and still benefit from the vault, quality gates, and verification.

**Does Sentinel modify my code?**
Never. Sentinel only reads your code (for drift detection, fact checking, and impact analysis). It writes to the `vault/` directory and `.sentinel/` tracking directory — never to your source files.

**What if I don't like a quality gate warning?**
Warnings are advisory, not blocking. Sentinel exits with code 0 regardless — it tells you what it found, and you decide what to act on.

**Can I use Sentinel on an existing project?**
Yes. Run `/sentinel bootstrap` in any project. It creates the vault structure without touching existing files. Historical knowledge builds up naturally as you work.

**How do I measure if Sentinel is helping?**
Run `/sentinel stats`. It shows investigation resolution rates, gotcha surfacing frequency, test/lint compliance across sessions, and commit patterns. No guesswork — real data from real sessions.

**What happens if I uninstall Sentinel?**
Your `vault/` directory stays. It's your project's knowledge base — committed to git, readable by anyone. The `.sentinel/` directory can be safely deleted. Your code is unaffected.

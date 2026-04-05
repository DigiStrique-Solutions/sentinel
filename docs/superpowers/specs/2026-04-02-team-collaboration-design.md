# Team Collaboration Design — v0.5.0

Single release adding three team collaboration features to Sentinel: vault conflict resolution, team activity feed, and team onboarding.

## Target Users

- Small teams (2-3 devs) sharing one repo, all using Claude Code
- Larger teams (5-10+) with mixed Claude Code and non-Claude-Code users
- Both cases must work without extra tooling or infrastructure

## Feature 1: Vault Conflict Resolution

### Problem

When multiple developers contribute to the same vault, git merge conflicts can occur — especially on shared files like activity feeds, gotcha updates, or investigation status changes.

### Solution: Two-Layer Defense

**Layer 1 — One-file-per-entry (eliminates 90% of conflicts):**

Every vault entry is its own file. No hook or workflow appends to a shared file. Naming conventions:

| Vault type | Naming pattern | Example |
|-----------|---------------|---------|
| Gotchas | `vault/gotchas/<slug>.md` | `vault/gotchas/oauth-token-expiry.md` |
| Investigations | `vault/investigations/YYYY-MM-<slug>.md` | `vault/investigations/2026-04-sse-ordering.md` |
| Decisions | `vault/decisions/ADR-NNN-<slug>.md` | `vault/decisions/ADR-005-queue-backend.md` |
| Activity | `vault/activity/YYYY-MM-DD.md` | `vault/activity/2026-04-02.md` |
| Patterns | `vault/patterns/learned/<slug>.md` | `vault/patterns/learned/retry-with-backoff.md` |

Enforced in hooks — all vault writes use these patterns.

**Layer 2 — Git merge driver (safety net for remaining 10%):**

For cases where two devs touch the same file (same-day activity feed, updating the same gotcha):

- `.gitattributes` entry: `vault/**/*.md merge=sentinel-vault`
- Merge driver script: `scripts/vault-merge-driver.sh`

Merge driver behavior:
- Both sides added content (no deletions): concatenate both, deduplicate identical lines
- One side deleted, other edited: keep the edit (safer default)
- Adds `<!-- MERGE: review needed -->` comment when both sides' content is kept
- Next session's loader flags files with merge markers for human review

**Setup:**

- `/sentinel:bootstrap` (team preset) adds `.gitattributes` and instructs user to configure merge driver
- `/sentinel:doctor` verifies merge driver is configured
- Non-Claude-Code users set it up manually via `git config merge.sentinel-vault.driver`

### Files

| File | Type | Purpose |
|------|------|---------|
| `scripts/vault-merge-driver.sh` | New | Git merge driver for vault markdown |
| `templates/shared/gitattributes-team` | New | `.gitattributes` template |
| `commands/bootstrap.md` | Modified | Add merge driver setup to team preset |
| `commands/doctor.md` | Modified | Verify merge driver configuration |

---

## Feature 2: Team Activity Feed

### Problem

Team members don't know what other sessions have done — what gotchas were discovered, what investigations are open, what was committed. Knowledge is siloed.

### Solution: Daily Activity Files

Daily markdown files at `vault/activity/YYYY-MM-DD.md`. Each entry is a single line with timestamp, author, and event.

### File Format

```markdown
# Activity — 2026-04-02

- `14:32` **Sarah** — Discovered gotcha: `oauth-token-expiry` (vault/gotchas/oauth-token-expiry.md)
- `14:35` **Sarah** — Committed 8 files to `sentinel/2026-04-02-1432` [a1b2c3d]
- `15:10` **James** — Opened investigation: `sse-event-ordering` (vault/investigations/2026-04-sse-ordering.md)
- `15:45` **James** — Resolved investigation: `sse-event-ordering`
- `16:00` **Sarah** — Quality gate failure: no changelog entry for today
- `16:20` **James** — Committed 3 files to `fix/auth-bug` [d4e5f6g]
```

### Events Captured

| Event | Logged by | Trigger |
|-------|-----------|---------|
| Gotcha created/updated | `post-tool-tracker.sh` | Write to `vault/gotchas/` detected |
| Investigation opened/resolved | `post-tool-tracker.sh` | Write to `vault/investigations/` detected |
| Decision added/superseded | `post-tool-tracker.sh` | Write to `vault/decisions/` detected |
| Pattern extracted | `stop-pattern-extractor.sh` | Optional hook, end of session |
| Quality gate failure | `stop-enforcer.sh` | Gate check fails |
| Vault entries pruned | `session-start-prune.sh` | Auto-archive runs |
| Files committed | `stop-git.sh` | Auto-commit completes |
| Branch created | `session-start-git.sh` | Auto-branch on main |
| Worktree merged | `stop-merge.sh` | Worktree merged back |

### Attribution

Author name from `git config user.name`. Already configured on every dev machine — no extra setup.

### Activity Logger

A shared shell function `hooks/engine/activity-logger.sh` that all hooks source to append entries:

```bash
# Usage: log_activity "event description"
# Reads git user.name, appends timestamped line to today's activity file
```

All hooks that log events source this file and call `log_activity`. This avoids duplicating the logging logic across 7+ hooks.

### Session-Start Loading

`session-start-loader.sh` reads the last 3 days of activity files and includes a summary in the context output. Claude knows what the team has been doing recently.

### Pruning

`session-start-prune.sh` (Tier 1) archives activity files older than 30 days to `vault/.archive/activity/`.

### Files

| File | Type | Purpose |
|------|------|---------|
| `hooks/engine/activity-logger.sh` | New | Shared logging function |
| `templates/vault/activity/.gitkeep` | New | Directory placeholder |
| `hooks/engine/post-tool-tracker.sh` | Modified | Log vault events to activity feed |
| `hooks/engine/stop-git.sh` | Modified | Log commit to activity feed |
| `hooks/engine/stop-merge.sh` | Modified | Log merge to activity feed |
| `hooks/engine/stop-enforcer.sh` | Modified | Log gate failures to activity feed |
| `hooks/engine/session-start-git.sh` | Modified | Log branch creation to activity feed |
| `hooks/engine/session-start-loader.sh` | Modified | Load recent activity at session start |
| `hooks/engine/session-start-prune.sh` | Modified | Archive old activity files |

---

## Feature 3: Team Onboarding

### Problem

New team members install Sentinel but don't know team standards, recent context, or how to get started. The team manifest has onboarding config but nothing enforces or guides through it.

### Solution: Command + Passive Hook

**`/sentinel:onboard` command (guided):**

Steps:
1. **Check prerequisites** — Sentinel installed? Vault exists? Team manifest exists?
2. **Read required vault files** — Renders files from `manifest.json`'s `required_vault_read` (default: `quality/gates.md`, `quality/anti-patterns.md`). Outputs summary of each.
3. **Show recent activity** — Last 3 days of activity feed. New member sees what's happening.
4. **Configure settings** — If `shared/settings-template.json` exists, offers to merge into `~/.claude/settings.json`. Asks before overwriting.
5. **Suggest first task** — Points to `first_task_workflow` from manifest (default: `bug-fix`). Outputs the workflow.
6. **Mark onboarded** — Creates `.sentinel/onboarded-<git-username>` marker.
7. **Print summary** — Active gotchas count, open investigations count, team members active this week.

**Passive hook detection (fallback):**

Addition to `session-start-loader.sh`:
- Check if `templates/shared/manifest.json` exists (team preset active)
- Check if `.sentinel/onboarded-<git-username>` exists
- If not: output one-line nudge: `"TEAM ONBOARDING: You haven't completed team onboarding yet. Run /sentinel:onboard to get set up."`

Fires once per session until they run the command. Non-intrusive.

**Non-Claude-Code users:**

- Read vault files manually (they're just markdown)
- Set up merge driver via `git config` command
- `/sentinel:doctor` detects missing merge driver setup
- The onboard command detects non-Claude-Code context and outputs plain text instructions

### Files

| File | Type | Purpose |
|------|------|---------|
| `commands/onboard.md` | New | Guided onboarding command |
| `hooks/engine/session-start-loader.sh` | Modified | Onboarding check at session start |

---

## Complete File Change Summary

### New Files (5)

| File | Purpose |
|------|---------|
| `scripts/vault-merge-driver.sh` | Git merge driver for vault markdown files |
| `commands/onboard.md` | `/sentinel:onboard` guided team setup |
| `templates/shared/gitattributes-team` | `.gitattributes` template for merge driver |
| `hooks/engine/activity-logger.sh` | Shared function for activity feed logging |
| `templates/vault/activity/.gitkeep` | Directory placeholder for activity feed |

### Modified Files (8)

| File | Change |
|------|--------|
| `hooks/engine/post-tool-tracker.sh` | Add activity feed logging for vault events |
| `hooks/engine/stop-git.sh` | Log commit event to activity feed |
| `hooks/engine/stop-merge.sh` | Log merge event to activity feed |
| `hooks/engine/stop-enforcer.sh` | Log quality gate failures to activity feed |
| `hooks/engine/session-start-git.sh` | Log branch creation to activity feed |
| `hooks/engine/session-start-loader.sh` | Load recent activity + onboarding check |
| `hooks/engine/session-start-prune.sh` | Archive activity files >30 days |
| `commands/bootstrap.md` | Merge driver setup in team preset, activity dir creation |

### Version & Docs (4)

| File | Change |
|------|--------|
| `package.json` | Bump to 0.5.0 |
| `.claude-plugin/plugin.json` | Bump to 0.5.0 |
| `CHANGELOG.md` | v0.5.0 entry |
| `README.md` | Team collaboration docs, command count 6 to 7 |

### Total: 17 files (5 new + 8 modified + 4 version/docs)

---

## Decisions

1. **Daily activity files over single file** — Natural organization, avoids truncation logic, easy to prune by date. Merge conflicts limited to same-day entries (handled by merge driver).
2. **One-file-per-entry as primary conflict prevention** — Simpler than any merge strategy. Merge driver is safety net, not primary defense.
3. **Git merge driver over custom tooling** — Uses git's native extensibility. No daemon, no server, no extra process. Works for all team members regardless of whether they use Claude Code.
4. **Passive onboarding hook over blocking** — New members should be nudged, not blocked. The command exists for the full experience; the hook is a gentle reminder.
5. **Attribution via git config user.name** — Zero extra setup. Already configured on every dev machine.

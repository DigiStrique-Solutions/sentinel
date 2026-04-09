---
name: sentinel-health
description: Show Sentinel system health — vault status, hook activity, open investigations, stale entries, and coverage gaps.
---

# Health Command

Run a comprehensive health check of the Sentinel system and display a formatted dashboard. Check each section below and report results with pass/warn/fail indicators.

Use these indicators:
- `[PASS]` — Everything is healthy
- `[WARN]` — Works but needs attention
- `[FAIL]` — Broken or missing, needs fixing

## 1. Vault Health

Sentinel supports two vaults: the **repo vault** (`./vault/`) and an optional **global vault** (`~/.sentinel/vault/`). Report on both.

### Repo vault

Check the `vault/` directory in the project root.

- Does `vault/` exist? If not, report `[FAIL] Repo vault not found. Run /sentinel-bootstrap to create it.` and continue to the global vault check (don't stop — global vault may still exist).
- List directories present vs expected: investigations, gotchas, decisions, workflows, quality, patterns, architecture, changelog, context, completed, planning
- Count files in each directory (exclude _template.md and _example.md from counts)

### Global vault

Check `~/.sentinel/vault/` (or the path configured in `.sentinel/config.json` under `vault.global_path`).

- Does it exist? If not, report `[INFO] Global vault not configured. Run /sentinel-global-init to set one up.` (this is informational, not a failure — the global vault is optional)
- If `vault.global_enabled` is `false` in config, report `[INFO] Global vault disabled for this project`
- If it exists and is enabled, count files in investigations, gotchas, decisions, patterns/learned
- Report whether it's a git repo and whether it has a remote configured

Report both as a table:

```
Vault Health

Repo vault (./vault/)
Directory          Files  Status
investigations/    3      [PASS]
  resolved/        1      [PASS]
gotchas/           5      [PASS]
decisions/         2      [PASS]
workflows/         13     [PASS]
quality/           3      [PASS]
patterns/          0      [WARN] No patterns extracted yet
architecture/      0      [WARN] No architecture docs
changelog/         0      [WARN] No changelog entries

Global vault (~/.sentinel/vault/)
Status: enabled, git-tracked, remote configured
Directory          Files  Status
investigations/    1      [PASS]
gotchas/           8      [PASS]
decisions/         0      [INFO]
patterns/learned/  2      [PASS]
```

## 2. Open Investigations

List all files in `vault/investigations/` (excluding resolved/ subdirectory and templates).
For each, read the first few lines to extract Status and Date.
Report:

```
Open Investigations
File                              Status       Age
2026-03-sse-ordering.md          in-progress  3 days
2026-03-auth-redirect.md         open         7 days  [WARN: >7 days]
```

Flag investigations open longer than 7 days with a warning.

## 3. Quality Gate Status

Check for required quality files:
- `vault/quality/anti-patterns.md` — [PASS] or [FAIL]
- `vault/quality/test-standards.md` — [PASS] or [FAIL]
- `vault/quality/gates.md` — [PASS] or [FAIL]
- Count any additional custom quality files

```
Quality Gates
anti-patterns.md    [PASS]
test-standards.md   [PASS]
gates.md            [PASS]
Custom files: 2
```

## 4. Workflow Coverage

List all workflow files in `vault/workflows/`.
Flag if fewer than 3 workflows exist.
Check if CLAUDE.md references the workflows (search for `@vault/workflows/` or `vault/workflows/`).

```
Workflow Coverage
Installed: 13 workflows     [PASS]
CLAUDE.md references: Yes   [PASS]
```

## 5. Staleness Warnings

Check for stale entries that may need attention:

- **Gotchas**: List any gotchas with file modification dates older than 30 days
- **Investigations**: List any investigations open longer than 7 days
- **Session recovery**: Count files, report oldest

```
Staleness Warnings
Gotchas >30 days old:
  timezone-handling.md (45 days)        [WARN]
Investigations >7 days:
  2026-03-auth-redirect.md (7 days)    [WARN]
Session recovery files: 3 (oldest: 5 days)
```

## 6. Hook Health

Check `.claude/settings.json` for hook references:
- Count hooks registered in project settings.json (local hooks)
- Check for `.sentinel/` temp directory in project root — should not exist between sessions. If it exists, report `[WARN] Stale .sentinel/ directory found. Run /doctor to clean up.`

**Hook Overlap Detection** (critical):

Compare hooks in `.claude/settings.json` (project-local) against Sentinel's plugin `hooks.json`. Detect when both systems run hooks that do the same thing — this doubles timeout budget and causes duplicate state tracking.

For each lifecycle event (SessionStart, PreToolUse, PostToolUse, PreCompact, UserPromptSubmit, Stop), check if local hooks overlap with Sentinel plugin hooks by matching on PURPOSE (not just name). Known overlap pairs:

| Local hook pattern | Sentinel equivalent | Purpose |
|---|---|---|
| `session-start-sync` | `session-start-sync` | Config sync |
| `vault-loader` | `session-start-loader` | Vault context loading |
| `prompt-vault-checker` | `prompt-vault-search` | Vault search on prompt |
| `pre-compact-save` | `pre-compact-save` | Save before compaction |
| `gotcha-check` | `pre-tool-gotcha` | Gotcha injection |
| `todo-enforcer` | `pre-tool-scope` | Scope/todo nudge |
| `session-tracker` | `post-tool-tracker` | File modification tracking |
| `staleness-detector` | `post-tool-staleness` | Stale gotcha detection |
| `test-validator` | `post-tool-test-tracker` | Test file tracking |
| `design-reviewer` | `post-tool-design-check` | Frontend design nudge |
| `bash-test-tracker` | `post-tool-test-watch` | Test failure tracking |
| `todo-tracker` | `post-tool-todo-mirror` | Todo state mirroring |
| `stop-session-summary` | `stop-session-summary` | Session summary |
| `stop-vault-enforcer` | `stop-enforcer` | Quality gate enforcement |
| `stop-pattern-extractor` | `stop-pattern-extractor` | Pattern extraction |

For each local hook in settings.json, check if a Sentinel plugin hook covers the same purpose. Report:

```
Hook Overlap Detection
Local hooks in settings.json:    17
Sentinel plugin hooks:           25
Overlapping pairs found:         15    [FAIL] Remove local duplicates
Non-overlapping local hooks:      2    [WARN] Not covered by Sentinel

Overlapping hooks (remove from settings.json):
  session-start-sync.sh          ↔  engine/session-start-sync.sh
  session-start-vault-loader.sh  ↔  engine/session-start-loader.sh
  ...

Local-only hooks (no Sentinel equivalent):
  post-tool-connector-validator.sh  — domain-specific, keep in settings.json
  eval-tests-adversarial.sh         — no plugin equivalent yet
```

If overlapping hooks are found, report `[FAIL]` with instruction: "Remove duplicate hooks from .claude/settings.json. Sentinel plugin handles these."

```
Hook Health
Local hooks: 17                  [PASS]
.sentinel/ temp dir: clean       [PASS]
Hook overlaps: 15                [FAIL] Sentinel plugin duplicates found
```

## 7. CLAUDE.md Integration

Check if CLAUDE.md exists and contains Sentinel sections:
- Quality standards references (@vault/quality/)
- Workflow table
- Mandatory behaviors (investigation protocol, test failure protocol)

```
CLAUDE.md Integration
File exists: Yes                    [PASS]
Quality standards referenced: Yes   [PASS]
Workflows referenced: Yes           [PASS]
Mandatory behaviors: Yes            [PASS]
```

## 8. Summary

Print a one-line summary:
```
Sentinel Health: 6/7 checks passed, 1 warning. Run /doctor to fix issues.
```

If everything passes:
```
Sentinel Health: All checks passed. Vault is healthy.
```

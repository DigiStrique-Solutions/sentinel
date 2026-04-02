---
name: health
description: Show Sentinel system health — vault status, hook activity, open investigations, stale entries, and coverage gaps.
---

# Health Command

Run a comprehensive health check of the Sentinel system and display a formatted dashboard. Check each section below and report results with pass/warn/fail indicators.

Use these indicators:
- `[PASS]` — Everything is healthy
- `[WARN]` — Works but needs attention
- `[FAIL]` — Broken or missing, needs fixing

## 1. Vault Health

Check the `vault/` directory in the project root.

- Does `vault/` exist? If not, report `[FAIL] Vault not found. Run /bootstrap to create it.` and stop.
- List directories present vs expected: investigations, gotchas, decisions, workflows, quality, patterns, architecture, changelog, context, completed, planning
- Count files in each directory (exclude _template.md and _example.md from counts)
- Report as a table:

```
Vault Health
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

Check `.claude/settings.json` for Sentinel hook references:
- Are any hooks registered? List active hooks.
- Check for `.sentinel/` temp directory in project root — should not exist between sessions. If it exists, report `[WARN] Stale .sentinel/ directory found. Run /doctor to clean up.`

```
Hook Health
Registered hooks: 4          [PASS]
.sentinel/ temp dir: clean   [PASS]
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

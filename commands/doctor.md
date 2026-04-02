---
name: doctor
description: Diagnose and fix common Sentinel installation issues — missing files, broken hooks, stale state.
---

# Doctor Command

Diagnose and automatically fix common Sentinel installation issues. Report what was found and what was fixed.

## Step 1: Check Vault Exists

Check if `vault/` exists in the project root.

- If not, report: `[FAIL] No vault/ directory found. Run /bootstrap to create it.`
- Stop here — nothing else can be checked without a vault.

## Step 2: Check Expected Directories

Check each expected directory exists under `vault/`. Create any that are missing.

Expected directories:
- `investigations/`
- `investigations/resolved/`
- `gotchas/`
- `decisions/`
- `workflows/`
- `quality/`

Optional directories (create only if the project uses the standard or team preset):
- `patterns/`
- `patterns/learned/`
- `architecture/`
- `changelog/`
- `session-recovery/`
- `context/`
- `completed/`
- `planning/`
- `scripts/`
- `evals/`
- `design/`

Report:
```
Directory Check
investigations/          [PASS] exists
investigations/resolved/ [FIXED] created
gotchas/                 [PASS] exists
...
```

## Step 3: Check Template Files

Check required template files exist. If missing, read from the Sentinel plugin's `templates/vault/` directory and create them.

Required templates:
- `vault/investigations/_template.md`
- `vault/decisions/_template.md`

Report:
```
Template Check
investigations/_template.md  [PASS] exists
decisions/_template.md       [FIXED] created from plugin template
```

## Step 4: Check Quality Gate Files

Check quality files exist. If missing, read from the Sentinel plugin's `templates/vault/quality/` directory and create them.

Required quality files:
- `vault/quality/anti-patterns.md`
- `vault/quality/test-standards.md`
- `vault/quality/gates.md`

Report:
```
Quality Files
anti-patterns.md    [PASS] exists
test-standards.md   [PASS] exists
gates.md            [FIXED] created from plugin template
```

## Step 5: Check for Orphaned State

Check for `.sentinel/` directory in the project root. This is a temp directory used during sessions and should not persist.

- If found, delete it and report: `[FIXED] Cleaned up stale .sentinel/ directory`
- If not found: `[PASS] No stale temp state`

## Step 6: Check CLAUDE.md

Check if `CLAUDE.md` exists in the project root.

- If it exists, check if it references `vault/quality/` and `vault/workflows/`
- If references are missing, report: `[WARN] CLAUDE.md exists but doesn't reference vault. Consider adding quality standards and workflow references.`
- If CLAUDE.md doesn't exist: `[WARN] No CLAUDE.md found. Run /bootstrap to create one, or manually add vault references.`

## Step 7: Report Summary

Print a summary:
```
Doctor Summary
Checked: 15 items
Passed:  12
Fixed:   2
Warnings: 1

Fixed:
  - Created vault/investigations/resolved/ directory
  - Created vault/quality/gates.md from template

Warnings:
  - CLAUDE.md doesn't reference vault workflows

No manual action required.
```

Or if there are items needing manual attention:
```
Manual action needed:
  - Add vault references to CLAUDE.md (see /bootstrap for the template)
```

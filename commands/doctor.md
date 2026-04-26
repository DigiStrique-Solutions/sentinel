---
name: sentinel-doctor
description: Diagnose and fix common Sentinel installation issues — missing files, broken hooks, stale state.
---

# Doctor Command

Diagnose and automatically fix common Sentinel installation issues. Report what was found and what was fixed.

## Flags

- `--uninstall-check` — skip the normal diagnostic flow and instead run the uninstall discovery in read-only mode. Prints a report of every Sentinel artifact found in the project (and globally, if paired with `--global`) without modifying anything. Use this to preview what `/sentinel-uninstall` would touch before running it for real.

## Flag handling: `--uninstall-check`

If `--uninstall-check` is passed, skip all other steps and instead run:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/uninstall-helpers.sh" discover-project "$(pwd)"
```

Parse the JSON output and render it as the same human-readable report that `/sentinel-uninstall` Step 1 shows. If `--global` is also passed, also run `discover-global` and include a global section. End with:

```
This was a dry run — nothing was modified.

To actually uninstall: /sentinel-uninstall
To preview actions:     /sentinel-uninstall --dry-run
```

Do not run the rest of the doctor flow when `--uninstall-check` is set.

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

## Step 5: Check for Orphaned Session State

Check `.sentinel/sessions/` for stale session files (PIDs that are no longer running).

- For each `.json` file in `.sentinel/sessions/`, check if the `pid` is still alive with `kill -0`
- If dead, delete the `.json` file and its matching directory
- Report: `[FIXED] Cleaned up N stale session(s)` or `[PASS] No stale session state`

**Do NOT delete the `.sentinel/` directory itself.** It contains persistent state:
- `.sentinel/config.json` — user preferences from `/sentinel-config`
- `.sentinel/session-count` — pruning counter
- `.sentinel/loop/` — active loop state from `/sentinel-loop`
- `.sentinel/batch/` — active batch state from `/sentinel-batch`
- `.sentinel/fact-checks.yml` — project-specific fact check rules

## Step 5b: Check `.sentinel/config.json`

The four optional hooks (`pattern_extraction`, `vault_search_on_prompt`, `session_summary`, `design_review_reminder`) are pre-registered in `hooks/hooks.json`, but each one self-guards by reading `.sentinel/config.json`. If that file is missing or has missing keys, the hooks exit silently and Sentinel's self-learning features go dark.

This step detects that condition and heals it.

**Detection logic:**

1. Check if `.sentinel/config.json` exists.

   - If **missing**: report
     ```
     Configuration File
     .sentinel/config.json    [MISSING] optional hooks are silently disabled
     ```
     Then offer to fix:
     ```
     Sentinel's self-learning hooks (pattern extraction, vault search, session summary)
     require .sentinel/config.json to activate. Without it, they exit silently.

     Create config.json with sensible defaults? (Y/n)
     ```
     If yes, run:
     ```bash
     bash "${CLAUDE_PLUGIN_ROOT}/scripts/init-config.sh" "$(pwd)" standard heal
     ```
     Parse the JSON output and report which hooks were enabled.

2. If config.json **exists**, run the heal mode anyway to detect missing keys (the schema may have grown since the user's config was first written):
   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}/scripts/init-config.sh" "$(pwd)" "<preset>" heal
   ```
   Where `<preset>` is read from `.sentinel/config.json`'s `preset` field, falling back to `standard` if absent.

   Parse the JSON output:
   - If `healed: true`, report:
     ```
     Configuration File
     .sentinel/config.json    [FIXED] added missing keys: hooks.pattern_extraction, thresholds.gotcha_staleness_days
     ```
   - If `skipped: true`, report:
     ```
     Configuration File
     .sentinel/config.json    [PASS] all keys present, N hooks enabled
     ```

**Why this matters:** users who installed Sentinel before bootstrap was fixed (or who deleted their config) currently have zero self-learning. This step is the safety net that gets them whole without a re-bootstrap.

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

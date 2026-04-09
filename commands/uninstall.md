---
name: sentinel-uninstall
description: Cleanly uninstall Sentinel by reverting every mutation it made to your project, with mandatory backups and per-category confirmation. Run this BEFORE `claude plugin uninstall sentinel@strique-marketplace`.
---

# Uninstall Command

This command helps you cleanly remove Sentinel from a project by reverting every mutation it made — vault directories, CLAUDE.md sections, `.claude/settings.json` permissions, `.gitattributes` entries, git config merge drivers, Sentinel branches, and state files. It does **not** uninstall the plugin itself; that's the final step you run in your terminal.

## What this command does

1. **Pre-flight checks** — refuses to run against a dirty git tree or without `jq` available
2. **Discovery** — scans the project for every Sentinel artifact and prints a report
3. **Interactive confirmation** — walks you through each category and asks keep / delete / revert
4. **Mandatory backup** — tars up everything that will be touched to `~/.sentinel/backups/` before any destructive action
5. **Execution** — performs the chosen actions via `scripts/uninstall-helpers.sh`
6. **Next steps** — tells you to run `claude plugin uninstall sentinel@strique-marketplace` as the final step

All the discovery and revert logic lives in `${CLAUDE_PLUGIN_ROOT}/scripts/uninstall-helpers.sh`. This command is just the interactive driver.

## Flags

- `--dry-run` — print every action without executing anything (no files modified, no backups created)
- `--all` — skip per-category prompts and use safe defaults: revert pollution (CLAUDE.md, settings.json, .gitattributes, git config, merge driver, merged sentinel branches) but **keep** the vault, .sentinel/ state, and global vault by default
- `--global` — also clean up home-directory state (`~/.sentinel/`, `~/.claude/.sentinel-sync-version`). Global vault deletion still requires explicit confirmation even with this flag.

## Step 0: Parse flags and run pre-flight

Parse `--dry-run`, `--all`, `--global` from the invocation. Set `DRY_RUN=1` as an env var if `--dry-run` is present (all helpers respect this).

Run:
```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/uninstall-helpers.sh" preflight-check "$(pwd)"
```

If it exits non-zero, print the error and stop. Do not attempt any further action.

## Step 1: Discovery

Run:
```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/uninstall-helpers.sh" discover-project "$(pwd)"
```

Parse the JSON output and render it as a human-readable report:

```
Sentinel discovery for <repo-name> at <cwd>:

  Vault:                    ./vault/       — 47 files, 312 KB
  State directory:          ./.sentinel/    — 3 active sessions
  CLAUDE.md sections:       4 Sentinel-added sections detected
                              - ## Quality Standards (auto-loaded)
                              - ## Workflows — Read Before Starting Work
                              - ## Mandatory Behaviors
                              - ## Critical Rules
  Settings permissions:     76 Sentinel-added permission patterns in .claude/settings.json
  .gitattributes:           sentinel-vault merge driver line present
  Git config:               merge.sentinel-vault.driver set
  Merge driver script:      scripts/vault-merge-driver.sh present
  Team shared dir:          .claude/shared/ present
  Git branches:             14 sentinel/*, 2 autoresearch/*
  Ejected files:            0 hooks, 0 agents, 0 skills, 0 rules
```

Only show rows where the value is present/non-zero. If nothing was found, print:

```
No Sentinel artifacts found in this project. Nothing to clean up.
You can now run: claude plugin uninstall sentinel@strique-marketplace
```

and stop.

If `--global` was passed, also run `discover-global` and append a "Global state" section to the report.

## Step 2: Per-category prompts (unless `--all`)

For each category that was found, ask the user what to do. Use these defaults (shown as **bold**):

| Category | Options | Default | Notes |
|---|---|---|---|
| Vault (`./vault/`) | keep / delete / archive | **keep** | User data. Deletion requires typing the repo name to confirm. |
| State directory (`./.sentinel/`) | **delete** / keep | delete | Session tracking, safe to remove |
| CLAUDE.md sections | **revert** / keep | revert | Heuristic — shows each section before removing |
| `.claude/settings.json` permissions | **revert** / keep | revert | Precise — uses the exact patterns from `configure-permissions.sh` |
| `.gitattributes` line | **revert** / keep | revert | Single line, trivially safe |
| Git config merge driver | **revert** / keep | revert | Single `git config --unset` |
| Merge driver script | **delete** / keep | delete | Plugin-provided, not user code |
| `.claude/shared/` dir | **delete** / keep | delete | Team preset asset |
| Git branches (merged) | **delete** / keep / delete-all | delete merged only | `delete-all` force-deletes unmerged branches too (requires confirmation) |
| Ejected plugin files | keep / delete | **keep** | If user ran `/sentinel-eject`, these are now their own files |

For **vault deletion**, prompt:
```
You're about to delete ./vault/ (47 files, 312 KB).
This contains your investigations, gotchas, decisions, and workflows.

To confirm, type the repo name exactly: <repo-name>
>
```
Only proceed if the input matches exactly. Any other input → skip.

For **delete-all branches**, prompt:
```
This will force-delete ALL sentinel/* and autoresearch/* branches,
including any that are NOT merged into main. You may lose work.

Type 'force delete branches' to confirm:
>
```

If `--all` is passed, skip the per-category prompts entirely and apply the defaults from the table — but still enforce the "type the repo name" check on vault deletion, and still refuse to force-delete unmerged branches.

## Step 3: Create backup

Before any destructive action runs, create a mandatory backup:

```bash
backup_path=$(bash "${CLAUDE_PLUGIN_ROOT}/scripts/uninstall-helpers.sh" create-backup "$(pwd)")
```

If the backup command fails, **abort the entire operation**. Do not run any revert action without a backup on disk. Print:

```
ERROR: Backup creation failed. Aborting uninstall — no changes made.
Please ensure ~/.sentinel/backups/ is writable and try again.
```

If `--dry-run`, the backup command prints what it would do without creating anything. That's fine; continue to the dry-run of each action.

Print the backup path prominently:
```
Backup created: ~/.sentinel/backups/sentinel-backup-<repo>-<timestamp>.tar.gz
Keep this until you're sure the uninstall was clean.
```

## Step 4: Execute chosen actions

For each category the user opted into, run the corresponding helper command:

```bash
HELPER="${CLAUDE_PLUGIN_ROOT}/scripts/uninstall-helpers.sh"

# Execute only the actions the user chose
bash "$HELPER" revert-claude-md "$(pwd)"          # if chose revert
bash "$HELPER" revert-settings-json "$(pwd)"       # if chose revert
bash "$HELPER" revert-gitattributes "$(pwd)"       # if chose revert
bash "$HELPER" revert-git-config "$(pwd)"          # if chose revert
bash "$HELPER" delete-merge-driver-script "$(pwd)" # if chose delete
bash "$HELPER" delete-shared-dir "$(pwd)"          # if chose delete
bash "$HELPER" delete-sentinel-state "$(pwd)"      # if chose delete
bash "$HELPER" delete-vault "$(pwd)"               # if chose delete
bash "$HELPER" delete-git-branches "$(pwd)" merged-only  # or 'all'
```

Each helper prints `[uninstall] <what it did>` to stderr. Capture those lines for the final summary.

## Step 5: Global cleanup (if `--global` was passed)

Only if the user passed `--global`:

1. **Plugin data** (`~/.sentinel/` except backups/ and vault/) — ask, default delete:
   ```bash
   bash "$HELPER" delete-plugin-data
   ```

2. **Sync version marker** — ask, default revert:
   ```bash
   bash "$HELPER" revert-global-claude-settings
   ```

3. **Global vault** — ask with the extra confirmation gate. Prompt:
   ```
   The global vault at ~/.sentinel/vault/ applies across ALL your projects
   and contains <N> files. Deleting it is NOT reversible from this backup
   alone — this backup only covers the current project.

   Type exactly "delete my global vault" to confirm:
   >
   ```
   Only run `bash "$HELPER" delete-global-vault` if the input matches exactly.

## Step 6: Summary and next steps

Print:
```
Sentinel cleanup complete for <repo-name>.

Reverted:
  - CLAUDE.md: removed 4 sections
  - .claude/settings.json: removed 76 permissions
  - .gitattributes: removed sentinel-vault line
  - Git config: removed merge driver
  - Merge driver script: deleted scripts/vault-merge-driver.sh
  - Git branches: deleted 12 merged sentinel/* branches

Preserved (your choice):
  - ./vault/ (47 files)
  - ~/.sentinel/vault/ (global)

Backup: ~/.sentinel/backups/sentinel-backup-<repo>-<timestamp>.tar.gz
Keep this until you're confident the uninstall was clean.

Next step: uninstall the plugin itself.
  claude plugin uninstall sentinel@strique-marketplace

Claude Code will remove the plugin files (hooks, commands, skills, agents, rules).
No further action needed.
```

If `--dry-run` was passed, prefix the summary with:
```
[DRY RUN] No files were modified. Re-run without --dry-run to execute.
```

## Error handling

- If any helper command fails mid-execution, stop immediately, print which step failed, and tell the user the backup path so they can restore manually.
- Do not continue past a failure — partial uninstalls are worse than no uninstall.
- If the backup file doesn't exist when expected (e.g., tar failed silently), abort.

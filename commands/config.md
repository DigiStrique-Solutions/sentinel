---
name: sentinel-config
description: Enable/disable optional Sentinel hooks and configure thresholds.
---

# Config Command

Configure optional Sentinel hooks and behavioral thresholds. Settings are saved to `.sentinel/config.json` in the project root.

## Step 1: Load Current Configuration

Read `.sentinel/config.json` if it exists.

**If it does not exist**, this is a sign the user installed Sentinel before bootstrap was fixed (or never ran bootstrap). Tell the user:

```
.sentinel/config.json is missing. The four optional hooks are pre-registered
but silently disabled until this file exists.

Run /sentinel-bootstrap to set up properly, or run /sentinel-doctor to heal
this in place. /sentinel-config can also create it now with standard defaults
(matching what /sentinel-bootstrap would write for the "standard" preset).

Create .sentinel/config.json with standard defaults now? (Y/n)
```

If yes, run:
```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/init-config.sh" "$(pwd)" standard init
```

Then continue with Step 2 using the just-written file. If no, proceed showing the user the in-memory defaults below — but make clear nothing is persisted until they save in Step 5.

The standard defaults (matching `templates/presets/standard.json`'s `hooks_config`):

```json
{
  "preset": "standard",
  "vault": {
    "repo_path": "vault",
    "global_enabled": true,
    "global_path": "~/.sentinel/vault"
  },
  "hooks": {
    "git_autopilot": true,
    "vault_search_on_prompt": true,
    "pattern_extraction": true,
    "session_summary": true,
    "design_review_reminder": false
  },
  "thresholds": {
    "scope_warning_files": 3,
    "test_failure_warning": 2,
    "gotcha_staleness_days": 30,
    "investigation_warning_days": 7
  }
}
```

## Step 2: Show Current Settings

Display the actual configuration loaded from `.sentinel/config.json` (don't hardcode states — read the file). Example with standard defaults:

```
Sentinel Configuration  (preset: standard)

Vault:
  Repo vault path:                        ./vault/
  Global vault enabled:                   ON
  Global vault path:                      ~/.sentinel/vault/

Core Hooks:
  Git Autopilot (auto-branch + auto-commit):  ON

Optional Hooks:
  Vault search on prompt submit:          ON
  Pattern extraction on session end:      ON
  Session summary on session end:         ON
  Design review reminder for .tsx/.css:   OFF

Thresholds:
  Scope warning (files without TodoWrite): 3
  Test failure warning (consecutive):      2
  Gotcha staleness (days):                 30
  Investigation warning (days open):       7
```

For each hook, render `ON` if `.hooks.<key> == true`, else `OFF`. The "ON/OFF" labels must reflect the file, not a hardcoded default.

## Step 3a: Configure Vault

Ask if the user wants to change vault settings.

1. **Global vault enabled** — When ON (default), the personal global vault at `~/.sentinel/vault/` is loaded in every session alongside the repo vault. Entries from the global vault are tagged `[global]` in session output so you can tell them apart. Turn OFF if you don't want cross-repo knowledge loaded into this specific project.

2. **Global vault path** — Where the global vault lives. Default: `~/.sentinel/vault/`. Change this if you keep your personal vault somewhere else (e.g., inside a Dropbox/iCloud folder, or a dedicated git repo elsewhere).

3. **Repo vault path** — Where this repo's vault lives. Default: `vault` (relative to the repo root). You usually don't need to change this.

If the user updates any of these, save them to `.sentinel/config.json` under the `vault` key.

## Step 3b: Configure Hooks

Ask the user which hooks to toggle. Present each hook with its current state and a description:

1. **Git Autopilot** (session-start-git.sh + stop-git.sh) — Auto-creates a branch when sessions start on main/master, and auto-commits all changes when sessions end. Enabled by default. Disable if you prefer to manage git yourself.

2. **Pattern extraction** (stop-pattern-extractor.sh) — When a session ends, automatically extract reusable patterns from the work done and save them to `vault/patterns/learned/`. Useful for building up project-specific knowledge over time.

3. **Session summary** (stop-session-summary.sh) — When a session ends, save a summary of what was done to `vault/session-recovery/`. Useful for picking up where you left off in a new session.

4. **Vault search on prompt** (prompt-vault-search.sh) — Before processing each prompt, search `vault/gotchas/` and `vault/investigations/` for relevant entries. Adds latency but prevents repeating known mistakes.

5. **Design review reminder** (post-tool-design-check.sh) — After editing `.tsx` or `.css` files, remind to run design review. Only useful for frontend projects.

Let the user toggle each one on/off.

## Step 4: Configure Thresholds

Ask if the user wants to adjust thresholds:

1. **Scope warning threshold** — How many files can be changed without a TodoWrite before warning. Default: 3.

2. **Test failure warning** — How many consecutive test failures before suggesting a fresh session. Default: 2.

3. **Gotcha staleness** — How many days before a gotcha is flagged as potentially stale. Default: 30.

4. **Investigation warning** — How many days an investigation can stay open before flagging. Default: 7.

## Step 5: Save

Write the updated configuration to `.sentinel/config.json`.

Print:
```
Configuration saved to .sentinel/config.json

Changes:
  - Enabled: session_summary
  - Changed: gotcha_staleness_days 30 -> 60
```

If hooks were enabled or disabled, confirm:
```
Optional hooks are pre-registered and self-guarding. Changes take effect on next session start.
```

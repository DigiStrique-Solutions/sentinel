---
name: sentinel-config
description: Enable/disable optional Sentinel hooks and configure thresholds.
---

# Config Command

Configure optional Sentinel hooks and behavioral thresholds. Settings are saved to `.sentinel/config.json` in the project root.

## Step 1: Load Current Configuration

Read `.sentinel/config.json` if it exists. If not, use defaults:

```json
{
  "hooks": {
    "pattern_extraction": false,
    "session_summary": false,
    "vault_search_on_prompt": false,
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

Display the current configuration:

```
Sentinel Configuration

Optional Hooks:
  Pattern extraction on session end:      OFF
  Session summary on session end:         OFF
  Vault search on prompt submit:          OFF
  Design review reminder for .tsx/.css:   OFF

Thresholds:
  Scope warning (files without TodoWrite): 3
  Test failure warning (consecutive):      2
  Gotcha staleness (days):                 30
  Investigation warning (days open):       7
```

## Step 3: Configure Hooks

Ask the user which hooks to toggle. Present each optional hook with its current state and a description:

1. **Pattern extraction** (stop-pattern-extractor.sh) — When a session ends, automatically extract reusable patterns from the work done and save them to `vault/patterns/learned/`. Useful for building up project-specific knowledge over time.

2. **Session summary** (stop-session-summary.sh) — When a session ends, save a summary of what was done to `vault/session-recovery/`. Useful for picking up where you left off in a new session.

3. **Vault search on prompt** (prompt-vault-search.sh) — Before processing each prompt, search `vault/gotchas/` and `vault/investigations/` for relevant entries. Adds latency but prevents repeating known mistakes.

4. **Design review reminder** (post-tool-design-check.sh) — After editing `.tsx` or `.css` files, remind to run design review. Only useful for frontend projects.

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

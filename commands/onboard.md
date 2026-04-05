---
name: onboard
description: Guided team onboarding for new Sentinel users
---

# /sentinel:onboard

Walk a new team member through Sentinel setup, team standards, and recent context.

## Steps

### Step 1: Check Prerequisites

Check that the environment is ready:

- [ ] Sentinel plugin is installed (you're reading this, so it is)
- [ ] A vault directory exists at `vault/` — if not, tell the user to run `/sentinel:bootstrap` first
- [ ] A team manifest exists at `.claude/shared/manifest.json` or `templates/shared/manifest.json` in the vault — if not, warn that this project may not be using the team preset

If no vault exists, stop and tell the user:
> "No vault found. Run `/sentinel:bootstrap` and select the **team** preset to set up your project for team collaboration."

### Step 2: Read Required Vault Files

Read the team manifest to find `onboarding.required_vault_read`. Default files if not specified:
- `vault/quality/gates.md`
- `vault/quality/anti-patterns.md`

For each required file:
1. Read the file
2. Output a 2-3 sentence summary of what it contains and why it matters
3. Highlight the most important rule or constraint

Example output:
> **Quality Gates** (`vault/quality/gates.md`): 7 sequential checks that must pass before work is declared complete. Most important: Gate 1 (all tests pass) and Gate 3 (correct fix, not a workaround).

### Step 3: Show Recent Activity

Read the last 3 days of activity files from `vault/activity/`:
- If activity files exist, output them so the new member sees what the team has been doing
- If no activity files exist, note that the activity feed will populate as the team works
- Highlight any open investigations or recently discovered gotchas

### Step 4: Configure Settings

Check if `templates/shared/settings-template.json` or `.claude/shared/settings-template.json` exists:
- If yes, read it and explain what settings it contains
- Ask the user: "Would you like to apply these team settings to your Claude Code configuration?"
- If user agrees, merge the settings into `~/.claude/settings.json` (preserve existing settings, only add/override team ones)
- If user declines, skip

### Step 5: Check Merge Driver

Check if the git merge driver for vault files is configured:

```bash
git config merge.sentinel-vault.driver
```

If not configured:
1. Explain why it matters: "The merge driver prevents git conflicts when multiple team members edit vault files simultaneously."
2. Output the setup command:
   ```
   git config merge.sentinel-vault.driver "$(git rev-parse --show-toplevel)/scripts/vault-merge-driver.sh %O %A %B"
   ```
3. Check if `.gitattributes` has the vault merge rule. If not, add it from `templates/shared/gitattributes-team`.

### Step 6: Suggest First Task

Read `first_task_workflow` from the team manifest (default: `bug-fix`).
- Read the corresponding workflow file from `vault/workflows/`
- Output a brief overview: "Your first task should follow the **Bug Fix** workflow. Here's the process: ..."
- List the key steps without the full checklist

### Step 7: Mark Onboarded

Get the git username:
```bash
git config user.name
```

Create the marker file `.sentinel/onboarded-<username>` (replace spaces with dashes, lowercase).

If `.sentinel/` doesn't exist, create it.

### Step 8: Print Summary

Output a summary:
> **Onboarding complete!**
>
> - **X** active gotchas to be aware of (in `vault/gotchas/`)
> - **Y** open investigations (in `vault/investigations/`)
> - **Z** team members active this week (from activity feed)
>
> Your work will be automatically tracked in the activity feed.
> Commits happen automatically when your session ends.
> Run `/sentinel:health` to check vault status anytime.

Count gotchas by listing `vault/gotchas/*.md` (excluding templates).
Count open investigations by grepping for files without `status: resolved`.
Count active team members by reading recent activity files and extracting unique author names.

## Non-Claude-Code Users

If this command is referenced outside of Claude Code (e.g., someone reads the file directly), the key setup steps are:

1. Read `vault/quality/gates.md` and `vault/quality/anti-patterns.md`
2. Configure the merge driver:
   ```bash
   git config merge.sentinel-vault.driver "$(git rev-parse --show-toplevel)/scripts/vault-merge-driver.sh %O %A %B"
   ```
3. Ensure `.gitattributes` includes `vault/**/*.md merge=sentinel-vault`
4. Read the last few days of `vault/activity/` to see what the team is working on

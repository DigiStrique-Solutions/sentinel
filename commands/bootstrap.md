---
name: sentinel bootstrap
description: Scaffold the Sentinel vault, workflows, and quality gates for a new project. Run once per project.
---

# Bootstrap Command

You are scaffolding a new Sentinel vault for this project. Follow these steps exactly.

## Step 1: Check for Existing Vault

Check if a `vault/` directory already exists in the project root.

- If it exists, ask: "Vault already exists. Reinitialize? (This won't delete existing files, only add missing ones)"
- If the user declines, stop.
- If the user agrees or no vault exists, continue.

## Step 2: Choose a Preset

Ask the user to choose a preset:

**minimal** — Vault skeleton + bug-fix workflow + quality gates. Best for trying Sentinel.

**standard** — Full vault + 13 workflows + quality gates + CLAUDE.md skeleton. Best for solo developers.

**team** — Standard + shared sync manifest + team onboarding config. Best for teams.

## Step 3: Read the Preset

Read the preset JSON from the Sentinel plugin's `templates/presets/` directory:
- `templates/presets/minimal.json`
- `templates/presets/standard.json`
- `templates/presets/team.json`

The preset defines which directories, templates, and workflows to create.

If the preset has `"extends"`, read the base preset first and merge.

## Step 4: Create Vault Directory Structure

Create all directories listed in the preset's `vault_dirs` array under `vault/`.

For the team preset, also create the directories listed in `additional_dirs`.

## Step 5: Copy Template Files

For each template listed in the preset's `templates` array:
1. Read the template from the Sentinel plugin's `templates/vault/` directory
2. Write it to `vault/` in the project, preserving the relative path
3. If the file already exists, skip it (don't overwrite)

For each workflow listed in the preset's `workflows` array:
1. Read the workflow from the Sentinel plugin's `templates/workflows/` directory
2. Write it to `vault/workflows/` in the project
3. If the file already exists, skip it

For team preset, also copy files from `additional_templates`.

## Step 5b: Team Preset — Additional Setup

If the team preset was selected, perform these additional steps:

1. **Create activity directory**: Create `vault/activity/` for the team activity feed
2. **Copy .gitattributes**: Copy `templates/shared/gitattributes-team` to the project root as `.gitattributes` (or append to existing `.gitattributes`)
3. **Configure merge driver**: Output the merge driver setup command:
   ```
   git config merge.sentinel-vault.driver "$(git rev-parse --show-toplevel)/scripts/vault-merge-driver.sh %O %A %B"
   ```
   Also copy `scripts/vault-merge-driver.sh` from the plugin to the project's `scripts/` directory and make it executable.
4. **Copy team manifest**: Copy `templates/shared/manifest.json` to `.claude/shared/manifest.json` if it doesn't exist

## Step 6: Create CLAUDE.md Skeleton

Read the CLAUDE.md template from `templates/claude-md/{preset.claude_md}`.

If a `CLAUDE.md` already exists in the project root:
- Ask: "CLAUDE.md already exists. Append Sentinel sections? (Quality standards, workflows, mandatory behaviors)"
- If yes, append the relevant sections (don't duplicate if already present)
- If no, skip

If no `CLAUDE.md` exists, create it from the template.

## Step 7: Create vault/README.md

Write a `vault/README.md` explaining the directory structure:

```markdown
# Vault

Knowledge vault for this project. Claude reads and writes here to maintain context across sessions.

## Directory Structure

| Directory | Purpose |
|-----------|---------|
| `investigations/` | Debugging journals — what was tried, what failed, why |
| `investigations/resolved/` | Completed investigations (moved here after resolution) |
| `gotchas/` | Non-obvious constraints and pitfalls |
| `decisions/` | Architecture Decision Records (ADRs) |
| `workflows/` | Step-by-step processes for common tasks |
| `quality/` | Anti-patterns, test standards, quality gates |
| `patterns/` | Reusable patterns extracted from sessions |
| `patterns/learned/` | Auto-extracted patterns with confidence scores |
| `architecture/` | System design and component documentation |
| `changelog/` | What changed and when |
| `session-recovery/` | Session state snapshots for recovery |
| `context/` | Service maps, DB schemas, env vars |
| `completed/` | Completed feature/task summaries |
| `planning/` | PRDs, task lists, implementation plans |
| `scripts/` | Utility scripts |
| `prompts/` | Curated user-facing prompts by vertical/persona |

## How It Works

- **Investigations** prevent repeating failed approaches across sessions
- **Gotchas** capture "this looks like it should work but doesn't because..."
- **Decisions** record why the code is structured a certain way
- **Quality gates** are checked before declaring work complete

See `vault/workflows/vault-maintenance.md` for the maintenance protocol.
```

Only include directories that were actually created (based on the preset).

## Step 8: Ask About Stack

Ask: "What's your tech stack?" with options:
- **Python** — Configures pytest, ruff commands in CLAUDE.md
- **TypeScript** — Configures jest/vitest, eslint commands in CLAUDE.md
- **Both** — Configures both sets of commands
- **Other** — Leave command placeholders for manual configuration

Update the CLAUDE.md with the appropriate test/lint commands based on the answer.

## Step 9: Print Summary

Print a summary of what was created:
- Number of directories created
- Number of template files created
- Number of workflows installed
- Whether CLAUDE.md was created or updated
- Stack configuration applied

## Step 10: Suggest Next Steps

Print:
```
Next steps:
1. Run `/health` to verify your setup
2. Review vault/quality/gates.md — these gates are checked before every task completion
3. Read vault/workflows/bug-fix.md to see the investigation protocol in action
4. Commit the vault/ directory to version control
```

For the **team** preset, add:
```
5. Run `/sentinel onboard` to complete team onboarding
6. Ask team members to run `/sentinel onboard` after installing Sentinel
7. Run `/sentinel doctor` to verify merge driver configuration
```

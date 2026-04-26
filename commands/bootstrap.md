---
name: sentinel-bootstrap
description: Scaffold the Sentinel vault, workflows, and quality gates for a new project. Run once per project.
---

# Bootstrap Command

You are scaffolding a new Sentinel vault for this project. Follow these steps exactly.

## Step 0: Pre-flight — Confirm the working directory

People often install Sentinel from a terminal and run `/sentinel-bootstrap` from whatever directory they happened to be in — not always a project root, and not always a git repo. Before touching anything, confirm.

1. Print the current working directory:
   ```
   Bootstrap will run in: <cwd>
   ```

2. Check if the cwd is inside a git repository (`git -C <cwd> rev-parse --is-inside-work-tree`).

   - **If NOT a git repo**, warn the user:
     ```
     WARNING: <cwd> is not a git repository.

     The vault will not be version-controlled here. If this isn't your project
     root, you should cd into the correct repo first.

     Continue anyway? (y/N)
     ```
     If the user declines, stop.

   - **If it IS a git repo but the cwd is NOT the repo root**, warn:
     ```
     NOTE: You're in a subdirectory of a git repo.
       cwd:       <cwd>
       repo root: <repo-root>

     The vault will be created at <cwd>/vault/, not at the repo root.
     Is this what you want? (y/N)
     ```
     If the user declines, stop.

3. Confirm the final vault path before doing anything:
   ```
   The vault will be created at: <cwd>/vault/
   Proceed? (y/N)
   ```

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

## Step 8b: Configure Permissions (Power User Setup)

This step auto-configures `.claude/settings.json` with `allowedTools` so Claude never hits permission walls for routine operations.

Run the configure-permissions script from the Sentinel plugin:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/configure-permissions.sh" "$(pwd)" "<stack>" "power-user"
```

Where `<stack>` is the answer from Step 8 (python, typescript, both, or other).

The script:
1. Detects the stack from Step 8
2. Builds a permission list covering all standard dev commands for that stack:
   - **Common**: git (non-destructive), file operations, search
   - **Python**: pytest, ruff, mypy, alembic, pip, venv, python
   - **TypeScript**: npm/yarn/pnpm, jest/vitest/playwright, eslint, tsc, next/vite
3. Writes or merges into `.claude/settings.json` under `permissions.allow`
4. Returns the count of permissions configured

This eliminates the #1 cause of Claude asking users to run commands: permission prompts blocking tool calls and causing Claude to fall back to suggesting instead of executing.

After the script runs, tell the user:

```
Configured N tool permissions in .claude/settings.json
Claude will now execute tests, lints, builds, and git commands autonomously — no permission prompts.
```

## Step 8c: Initialize `.sentinel/config.json` (enable optional hooks)

This is the step that makes Sentinel **self-learning out of the box**. Without it, the four optional hooks (pattern extraction, vault search on prompt, session summary, design review reminder) are pre-registered in `hooks/hooks.json` but each one self-guards by reading `.sentinel/config.json` — and exits silently if the file is missing. Result: nothing learns, no gotchas auto-create, no patterns get extracted.

Run the init-config script, passing the preset chosen in Step 2:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/init-config.sh" "$(pwd)" "<preset>" init
```

Where `<preset>` is `minimal`, `standard`, or `team` (the preset chosen in Step 2).

The script:
1. Reads the preset's `hooks_config` block (resolving `extends` if present)
2. Writes `.sentinel/config.json` with hooks, vault paths, and thresholds
3. Returns a JSON summary like:
   ```json
   {"created": true, "preset": "standard", "hooks_enabled": 4, "healed_keys": []}
   ```

If `.sentinel/config.json` already exists, the script is a no-op (skipped). User customizations are never trampled.

After the script runs, parse the JSON and tell the user:

```
Configured N optional hooks in .sentinel/config.json

Hooks now active for this project:
  vault_search_on_prompt   — search vault before each prompt for relevant context
  pattern_extraction       — auto-extract reusable patterns at session end
  session_summary          — save session summaries for cross-session continuity
  (design_review_reminder is OFF by default — toggle on with /sentinel-config if frontend project)

Sentinel will now learn from this project as you work. Gotchas, investigations,
and patterns accumulate automatically.
```

(Adjust the listed hooks based on which are actually enabled per preset — minimal only enables vault_search.)

## Step 8d: Offer Global Vault Setup

Sentinel supports a **global vault** at `~/.sentinel/vault/` for personal cross-repo knowledge — gotchas, investigations, and patterns that apply across every project you work on. This is separate from the repo vault just created.

Check if `~/.sentinel/vault/` already exists.

**If it exists**, just tell the user:
```
Global vault detected at ~/.sentinel/vault/ — it will be loaded alongside this repo's vault in every session.
```

**If it doesn't exist**, ask:
```
Sentinel supports a personal global vault for knowledge that applies across
all your projects (cross-repo gotchas, tooling quirks, personal conventions).
This is optional and fully separate from this repo's vault.

Set up a global vault now? (y/N)
```

If the user says yes, run `/sentinel-global-init` and follow its flow. If they say no, tell them:
```
Skipped. You can set it up any time with /sentinel-global-init.
```

## Step 9: Print Summary

Print a summary of what was created:
- Number of directories created
- Number of template files created
- Number of workflows installed
- Whether CLAUDE.md was created or updated
- Stack configuration applied
- Number of tool permissions configured
- **Number of optional hooks enabled** (from Step 8c)
- Global vault status (exists / newly created / skipped)

## Step 10: Suggest Next Steps

Print:
```
Next steps:
1. Run `/sentinel-doctor` to verify your setup (checks vault, hooks, config)
2. Review vault/quality/gates.md — these gates are checked before every task completion
3. Read vault/workflows/bug-fix.md to see the investigation protocol in action
4. Commit the vault/ directory to version control
5. Toggle optional hooks any time with `/sentinel-config`
```

For the **team** preset, add:
```
5. Run `/sentinel-onboard` to complete team onboarding
6. Ask team members to run `/sentinel-onboard` after installing Sentinel
7. Run `/sentinel-doctor` to verify merge driver configuration
```

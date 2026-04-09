---
name: sentinel-global-init
description: Scaffold a personal global vault at ~/.sentinel/vault/ for cross-repo knowledge that applies across all your projects.
---

# Global Vault Init

The global vault is a personal, cross-repo knowledge layer. It lives at `~/.sentinel/vault/` and is loaded into every session alongside the repo-specific vault. Use it for gotchas, investigations, and decisions that apply across multiple codebases.

This command scaffolds the global vault and (optionally) turns it into its own git repo so you can sync it across machines.

## Step 1: Check if the global vault already exists

Check for `~/.sentinel/vault/`. If it exists and contains any `.md` files, ask:

```
A global vault already exists at ~/.sentinel/vault/ with N entries.
Reinitialize? (This won't delete existing files, only add missing directories.)
```

If the user declines, stop.

## Step 2: Create the directory structure

Create these directories under `~/.sentinel/vault/`:

- `investigations/`
- `investigations/resolved/`
- `gotchas/`
- `decisions/`
- `patterns/learned/`

Write a `~/.sentinel/vault/README.md` explaining the purpose:

```markdown
# Global Sentinel Vault

Personal cross-repo knowledge loaded into every Sentinel session alongside repo-specific vaults.

## When to put something here

- **Gotchas** that apply to multiple projects (e.g., "macOS sed requires empty string arg for -i")
- **Investigations** of tooling, OS, or language quirks that bit you across projects
- **Decisions** about personal conventions (e.g., "I always use pnpm, never npm")
- **Patterns** you've learned that are language/framework-specific, not project-specific

## When NOT to put something here

- Anything tied to a specific repo's architecture, deploy, or business logic — that belongs in the repo vault
- Anything your teammates should see — put it in the repo vault and commit it

## Promoting from repo → global

Run `/sentinel-promote <file>` in any project to move a repo-vault file here.

## Sync across machines

If this directory is a git repo, `git pull` on each machine. See the output of `/sentinel-global-init` for setup instructions.
```

## Step 3: Ask about git sync

Ask:

```
Do you want to turn this into a git repo for cross-machine sync? (y/N)
```

If **no**, skip to Step 5.

If **yes**:

1. Run `git init` inside `~/.sentinel/vault/`
2. Write a `.gitignore` with `.index.json` and `.index-stale`
3. Stage everything and make an initial commit:
   ```
   git add -A
   git commit -m "chore: initialize global vault"
   ```

## Step 4: Ask about a remote

Ask:

```
Do you want to add a remote (GitHub/GitLab/etc.)? (y/N)
If yes, enter the remote URL (or leave blank to skip):
```

If the user provides a URL:

1. Run `git remote add origin <url>`
2. Run `git push -u origin main` (or `master`, whichever is the initial branch)
3. If the push fails, print the error and tell the user they may need to create the remote repo first.

## Step 5: Print summary

Print:

```
Global vault created at: ~/.sentinel/vault/
  - investigations/, gotchas/, decisions/, patterns/learned/
  - README.md

Git status: [initialized / not initialized]
Remote: [url / none]

Next steps:
1. Add cross-repo gotchas: write to ~/.sentinel/vault/gotchas/<name>.md
2. Or use /sentinel-promote <file> from any repo to move a file here
3. The global vault is loaded automatically at every session start

To disable the global vault in a specific project, run /sentinel-config and
toggle "Global vault" off.
```

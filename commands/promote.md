---
name: sentinel-promote
description: Move a vault file from the repo vault to the global vault (for cross-repo knowledge).
---

# Promote to Global Vault

Move a file from the repo vault (`./vault/`) to the global vault (`~/.sentinel/vault/`) when the knowledge it captures applies across multiple projects, not just this one.

## When to promote

- A gotcha about your OS, shell, or editor that bit you in this repo but would bite you anywhere (e.g., "macOS sed -i requires an empty string arg")
- An investigation into a tool/library quirk that isn't specific to this project's architecture
- A pattern you want available in every project you work on
- A personal convention you follow across all your work

## When NOT to promote

- Anything tied to this repo's architecture, data model, or business logic
- Anything your teammates need to see — commit it in the repo vault instead
- Anything that references specific files, functions, or IDs from this codebase

## Step 1: Parse the argument

The command expects a path argument, e.g.:

```
/sentinel-promote gotchas/macos-sed-inplace.md
/sentinel-promote vault/investigations/2026-03-timezone-parsing.md
```

Normalize the path:
- Strip a leading `vault/` if present
- Resolve against `./vault/` to get the absolute source path
- If the path doesn't exist, stop with an error: `File not found: <path>`

## Step 2: Check the global vault exists

Check `~/.sentinel/vault/`. If it doesn't exist, stop and tell the user:

```
Global vault not found. Run /sentinel-global-init first to set it up.
```

## Step 3: Compute the destination

The destination preserves the subdirectory structure:

```
./vault/gotchas/macos-sed.md → ~/.sentinel/vault/gotchas/macos-sed.md
./vault/investigations/2026-03-foo.md → ~/.sentinel/vault/investigations/2026-03-foo.md
```

If the destination already exists, ask:

```
A file with the same name exists in the global vault:
  ~/.sentinel/vault/gotchas/macos-sed.md

Overwrite? (y/N)
```

## Step 4: Confirm the promotion

Show the user what will happen:

```
Promote this file?
  From: ./vault/gotchas/macos-sed.md
  To:   ~/.sentinel/vault/gotchas/macos-sed.md

This will:
  1. Copy the file to the global vault
  2. Delete it from the repo vault
  3. Stage the deletion in the repo (so teammates see it's gone)
  4. Commit the addition in the global vault (if git-tracked)

Confirm? (y/N)
```

## Step 5: Execute the promotion

1. Create the destination directory if missing: `mkdir -p ~/.sentinel/vault/<subdir>`
2. Copy the file: `cp <src> <dst>`
3. Delete the source: `rm <src>`
4. Verify the destination exists and the source is gone. If anything looks wrong, restore the source and abort.

## Step 6: Git handling

**Global vault side** — if `~/.sentinel/vault/` is a git repo, commit the new file:

```
cd ~/.sentinel/vault
git add <path>
git commit -m "promote: add <filename> from <repo-name>"
```

If a remote is configured, offer to push:

```
Push to remote? (y/N)
```

**Repo vault side** — don't commit the deletion automatically. Git Autopilot will pick it up at session end. Just tell the user:

```
The file was removed from ./vault/. Git Autopilot will commit the deletion
when this session ends. Teammates who pull will stop seeing the file.
```

## Step 7: Print summary

```
Promoted: gotchas/macos-sed.md
  Source: ./vault/gotchas/macos-sed.md (removed)
  Destination: ~/.sentinel/vault/gotchas/macos-sed.md (added)
  Global vault git: [committed / not a git repo]
  Remote push: [pushed / skipped / not configured]

This file will now load in every session across all your projects.
```

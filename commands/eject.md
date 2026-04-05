---
name: sentinel-eject
description: Copy Sentinel plugin contents (hooks, agents, skills, rules) into your project for full customization. After ejecting, the plugin is no longer needed.
---

# Eject Command

Export all Sentinel plugin contents into project-owned files so the project no longer depends on the plugin. This is a one-way operation.

## Step 1: Warn

Print this warning:

```
WARNING: Ejecting copies all Sentinel plugin files into your project.

After ejecting:
- You own all the files and can customize them freely
- Plugin updates will NOT automatically apply to your project
- You can uninstall the Sentinel plugin

This is a one-way operation. The plugin itself is not modified.
```

Ask: "Proceed with eject? (yes/no)"

If no, stop.

## Step 2: Copy Hooks

Read all hook files from the Sentinel plugin's `hooks/` directory.
Write them to `.claude/hooks/` in the project root, preserving filenames.
Skip any that already exist (report as "skipped — already exists").

## Step 3: Copy Agents

Read all agent files from the Sentinel plugin's `agents/` directory.
Write them to `.claude/agents/` in the project root.
Skip any that already exist.

## Step 4: Copy Skills

Read all skill files from the Sentinel plugin's `skills/` directory.
Write them to `.claude/skills/` in the project root.
Skip any that already exist.

## Step 5: Copy Rules

Read all rule files from the Sentinel plugin's `rules/` directory.
Write them to `.claude/rules/` in the project root, preserving subdirectory structure.
Skip any that already exist.

## Step 6: Register Hooks

Read `.claude/settings.json` (create if it doesn't exist).
Add hook registrations for each ejected hook file.
Do not overwrite existing hook registrations.

## Step 7: Report

Print a summary:

```
Eject Complete

Copied:
  Hooks:  4 files -> .claude/hooks/
  Agents: 3 files -> .claude/agents/
  Skills: 2 files -> .claude/skills/
  Rules:  5 files -> .claude/rules/

Skipped (already exist):
  .claude/hooks/post-tool-design-check.sh

Hooks registered in .claude/settings.json

Next steps:
1. Review and customize the ejected files as needed
2. Commit the .claude/ directory to version control
3. You can now uninstall the Sentinel plugin if desired
4. Future updates must be applied manually by comparing with the plugin source
```

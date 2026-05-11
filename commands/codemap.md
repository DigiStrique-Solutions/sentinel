---
name: sentinel-codemap
description: Manage auto-refreshing codemaps. Register an existing /sentinel-batch output as a codemap, check drift status, or trigger a manual refresh. Once registered, codemap entries are automatically refreshed when source files change.
---

# Codemap Command

Track a codemap (or any per-file generated documentation produced by `/sentinel-batch`) so it stays in sync with the source. Once registered, two hooks (`session-start-codemap-check.sh`, `stop-codemap-refresh.sh`) detect drift from manual edits, `git pull`, and Claude Code edits, and refresh only the affected entries via a background API worker.

**Subcommands:**

- `/sentinel-codemap register <output_dir> --target <glob> --task "<prompt>" [--model <id>]`
- `/sentinel-codemap status [<output_dir>]`
- `/sentinel-codemap refresh [<output_dir>] [--dry-run]`
- `/sentinel-codemap list`

**Prerequisite for auto-refresh:** `hooks.codemap_refresh: true` in `.sentinel/config.json` and `ANTHROPIC_API_KEY` exported in the shell. Toggle via `/sentinel-config`.

## Parse Arguments

The first positional arg after `/sentinel-codemap` is the subcommand (`register`, `status`, `refresh`, `list`). Subsequent args depend on subcommand.

## Subcommand: register

**Purpose:** bootstrap a manifest from an existing batch output, so the hooks can auto-refresh it. Run this once, after `/sentinel-batch` has generated the initial codemap.

**Required args:**
- `output_dir` — relative or absolute path to where `/sentinel-batch` wrote results (e.g. `vault/codemap`)
- `--target <glob>` — the original glob passed to `/sentinel-batch` (e.g. `src/**/*.py`)
- `--task "<prompt>"` — the original task description passed to `/sentinel-batch`. This is stored in the manifest and used verbatim by the refresh worker.

**Optional:**
- `--model <id>` — Anthropic model to use for future refreshes. Defaults to `claude-haiku-4-5`. Override if the original batch used a different model.

**Execution:**

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/codemap-helpers.sh" register \
    "<output_dir>" "<task>" "<target_glob>" "<model>"
```

This scans `<output_dir>/results/` (or `<output_dir>/` if no `results/` subdir exists), matches each `.md` file back to a source path via the flat-name convention (`src--auth--login.py.md` → `src/auth/login.py`), computes the initial SHA256 of each matched source file, and writes `<output_dir>/.manifest.json`.

Report to the user:
```
Codemap registered.
  Manifest:     <output_dir>/.manifest.json
  Entries:      N source files tracked
  Unmatched:    M entries had no corresponding source file (orphans)
  Auto-refresh: ON  (or OFF — explain how to enable)
```

If `hooks.codemap_refresh` is `false`, suggest enabling via `/sentinel-config`.

## Subcommand: status

**Purpose:** show how much drift has accumulated since the last refresh.

**Args:** optional `output_dir`. If omitted, run status on every manifest under `vault/`.

**Execution:**

```bash
# If output_dir given:
bash "${CLAUDE_PLUGIN_ROOT}/scripts/codemap-helpers.sh" status "<output_dir>/.manifest.json"

# If not, list manifests and run status on each:
for m in $(bash "${CLAUDE_PLUGIN_ROOT}/scripts/codemap-helpers.sh" list-manifests "<project_dir>"); do
    bash "${CLAUDE_PLUGIN_ROOT}/scripts/codemap-helpers.sh" status "$m"
done
```

The helper prints a human-readable summary per manifest including counts of modified/added/deleted entries.

## Subcommand: refresh

**Purpose:** manually trigger a refresh (don't wait for the next session start / stop).

**Args:** optional `output_dir`, optional `--dry-run`.

**Execution:**

```bash
python3 "${CLAUDE_PLUGIN_ROOT}/scripts/refresh-codemap.py" \
    --manifest "<output_dir>/.manifest.json" \
    --project-root "<project_dir>" \
    ${DRY_RUN:+--dry-run}
```

This runs in the foreground (unlike the hook path), so the user sees progress directly. With `--dry-run`, the worker prints the drift classification as JSON and exits without calling the API or writing any files.

If no `output_dir` was given, iterate over all manifests under `vault/`.

## Subcommand: list

**Purpose:** show every registered codemap in the project.

**Execution:**

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/codemap-helpers.sh" list-manifests "<project_dir>"
```

Print each manifest path with a one-line summary (entry count + last refresh timestamp from the manifest).

## End-to-end example

```
# 1. Generate initial codemap (existing command, unchanged)
/sentinel-batch "generate a codemap summarizing each file's purpose, exports, and dependencies" \
    --target "src/**/*.py" --output vault/codemap

# 2. Register it for auto-refresh
/sentinel-codemap register vault/codemap \
    --target "src/**/*.py" \
    --task "generate a codemap summarizing each file's purpose, exports, and dependencies"

# 3. Enable the auto-refresh hooks (one-time per project)
/sentinel-config           # toggle: Codemap auto-refresh -> ON

# 4. (later) Check drift
/sentinel-codemap status

# 5. (later) Manually trigger a refresh
/sentinel-codemap refresh
```

After step 3, every subsequent session start scans for drift, and every session end refreshes any tracked entry Claude touched — in the background, without blocking the session.

## Key Rules

1. **One manifest per output directory.** Don't try to mix multiple codemaps in the same dir. Create separate output dirs for separate codemaps (e.g. `vault/codemap-backend/`, `vault/codemap-frontend/`).
2. **The task prompt is stored verbatim.** Whatever you pass to `--task` during register is exactly what the refresh worker sends to the API for every future regeneration. Phrase it as a per-file generation prompt.
3. **Flat-name convention is mandatory.** The helper assumes `/sentinel-batch`'s default `src--auth--login.py.md` naming. If you used a custom output format, register will mark them as unmatched and you'll need to manually edit the manifest.
4. **Auto-refresh requires both the config flag and the API key.** Either one missing → the hooks no-op silently. Run `/sentinel-doctor` if you're unsure why nothing is refreshing.
5. **Costs scale with drift, not repo size.** A typical refresh of 5 changed files in a 500-file repo costs ~$0.001 with `claude-haiku-4-5`. Full repo regeneration is via `/sentinel-batch`, not this command.

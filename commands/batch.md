---
name: sentinel-batch
description: Process a large task by breaking it into work items and grinding through them with sub-agents. For tasks too large for one context window — codemap generation, mass migration, bulk documentation.
---

# Batch Command

Break a large task into work items and process each one independently. Uses sub-agents for context isolation so a 500K-line codebase doesn't exhaust your context window.

**Usage:** `/sentinel-batch "<task>" --target "<glob>" [--output <dir>] [--parallel <N>]`

**Examples:**
```
/sentinel-batch "generate a codemap summarizing each file's purpose, exports, and dependencies" --target "src/**/*.py"
/sentinel-batch "add JSDoc comments to all exported functions" --target "src/**/*.ts" --parallel 3
/sentinel-batch "migrate from CommonJS to ESM" --target "src/**/*.js" --output vault/migrations/esm
/sentinel-batch "generate test stubs" --target "src/**/*.py" --output tests/stubs
/sentinel-batch "document each API endpoint" --target "src/controllers/**/*.py"
```

## Step 1: Parse Arguments

Extract from the user's message:
- **task**: What to do to each work item (required)
- **target**: Glob pattern for files to process (required)
- **output**: Where to write results (default: `.sentinel/batch/<id>/results/`)
- **parallel**: How many sub-agents to run concurrently (default: 1, max: 5)

If the user describes the task without explicit flags, infer them. For example:
- "generate codemaps for the entire src directory" → task: "generate codemap", target: "src/**/*"
- "add docstrings to all Python files" → task: "add docstrings", target: "**/*.py"

## Step 2: Discover Work Items

Run the glob pattern to find all matching files:

```bash
find <target_base> -type f -name "<pattern>" | sort
```

Or use the Glob tool with the pattern.

**Filter out:**
- Files in `node_modules/`, `.venv/`, `__pycache__/`, `.git/`, `dist/`, `build/`
- Files matching `.gitignore` patterns
- Files already processed (if resuming — check state file)

Count the total work items. If 0, report and stop.

If more than 500 files, warn the user:
```
Found <N> files matching <glob>. This will take a while.
Estimated: ~<N> sub-agent calls.
Continue? (You can narrow the target, e.g., "src/connectors/**/*.py")
```

## Step 3: Create State File

Generate a batch ID: `batch-<YYYY-MM-DD>-<short-random>`

Create the state directory and file:

```bash
mkdir -p .sentinel/batch/<id>/results
```

Write `.sentinel/batch/<id>/state.json`:

```json
{
  "type": "batch",
  "id": "<batch-id>",
  "task": "<task description>",
  "target": "<glob pattern>",
  "output_dir": ".sentinel/batch/<id>/results",
  "parallel": 1,
  "status": "running",
  "started_at": "<ISO timestamp>",
  "total": 150,
  "completed": 0,
  "failed": 0,
  "pending": 150,
  "items": [
    {"file": "src/main.py", "status": "pending"},
    {"file": "src/utils.py", "status": "pending"}
  ]
}
```

Print:
```
Batch <id> created: <total> files to process.
Task: <task>
Output: <output_dir>
```

## Step 4: Process Work Items

### Sequential mode (parallel: 1)

For each pending item:

#### 4a. Dispatch Sub-Agent

Use the Agent tool to dispatch a sub-agent for each file:

```
Agent(
  description: "Process <filename>",
  prompt: "Read the file at <absolute_path>. Then: <task>. Write the result to <output_dir>/<filename>.md. Output only the result, no preamble.",
  subagent_type: "general-purpose"
)
```

The sub-agent gets its own context window — it won't pollute the main session.

#### 4b. Update State

After the sub-agent returns:
- If successful: mark item as `"done"`, set `"output": "<result_path>"`
- If failed: mark item as `"error"`, set `"error": "<error message>"`
- Update counts: `completed++` or `failed++`, `pending--`
- Write updated state to disk immediately

#### 4c. Progress Report

Every 10 items (or every item if total < 20), print:
```
Progress: <completed>/<total> done, <failed> failed, <pending> remaining
```

### Parallel mode (parallel: 2-5)

Dispatch up to `parallel` sub-agents simultaneously using multiple Agent tool calls in a single message. Wait for all to complete, then update state and dispatch the next batch.

```
# Dispatch 3 at once:
Agent("Process file1.py", ...)
Agent("Process file2.py", ...)
Agent("Process file3.py", ...)
# Wait for all 3, update state, dispatch next 3
```

## Step 5: Aggregate Results (optional)

After all items are processed, if the task benefits from aggregation:

1. Read all result files from the output directory
2. Generate a summary/index file at `<output_dir>/INDEX.md`:

```markdown
# Batch Results — <task>

Generated: <timestamp>
Total: <N> files processed, <M> failed

## Files

| File | Status | Output |
|------|--------|--------|
| src/main.py | done | [result](results/src--main.py.md) |
| src/utils.py | done | [result](results/src--utils.py.md) |
| src/broken.py | error | Parse failed |
```

3. If the user's task was codemap/documentation generation, also generate a top-level summary by reading the per-file results (not the source files — the summaries) and synthesizing an architectural overview.

## Step 6: Completion

Update state file: `"status": "completed"` with `"completed_at": "<timestamp>"`

Print:
```
Batch COMPLETED.
  Processed: <completed>/<total>
  Failed: <failed>
  Output: <output_dir>
  Index: <output_dir>/INDEX.md

Results are in <output_dir>/. The state file will be cleaned up.
```

If failed > 0:
```
<failed> file(s) failed. Review errors:
  - src/broken.py: <error message>

Re-run failed items with: /sentinel-batch --resume <id> --retry-failed
```

Clean up state file only if 0 failures. Preserve it if there were failures (enables retry).

## Step 7: Resume

If the user runs `/sentinel-batch --resume [<id>]`:

1. If no id provided, find the most recent state file in `.sentinel/batch/`
2. Read the state file
3. If `completed` with 0 failures → "Already completed."
4. If `running` or has pending items → continue from where it left off
5. If `--retry-failed` flag → reset failed items to pending and reprocess

Print:
```
Resuming batch <id>: <pending> items remaining, <failed> to retry.
```

Continue from Step 4.

## Step 8: List (if --list flag)

If the user runs `/sentinel-batch --list`:

List all batch state files with their status:
```
Active batches:
  batch-2026-04-02-abc123  running   75/150 done  "generate codemaps"
  batch-2026-04-01-def456  completed 200/200 done  "add docstrings"
```

## Key Rules

1. **Sub-agents for isolation.** Each file gets its own context window via the Agent tool. Never process files in the main context — that's how you exhaust it.
2. **State file after every item.** Write to disk after each file is processed. If the session crashes, you resume from the last checkpoint — not from the beginning.
3. **Flatten output paths.** Convert `src/services/users/auth.py` to `src--services--users--auth.py.md` in the output directory to avoid nested directories.
4. **Don't read results into main context.** The aggregation step should use sub-agents too if the result set is large (>50 files). Only the INDEX.md summary comes back to the main context.
5. **Respect rate limits.** Parallel > 3 can cause issues. Default to 1, let users opt into parallelism.
6. **Skip binary files.** If a glob matches images, compiled files, or other non-text content, skip them silently.

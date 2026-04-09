---
name: sentinel-autoresearch
description: Autonomous score-driven optimization loop with git-backed keep/discard and an append-only ledger. Give it a task + a score command, and it iterates — keeping changes that improve the score, reverting ones that don't. For tuning prompts, fixing lint, optimizing perf, or any task with one comparable number.
---

# Autoresearch Command

Run an autonomous optimization loop. On each iteration, propose an edit, apply it, measure via the user's score command, and either **keep** it (commit to the run branch) or **discard** it (`git reset --hard HEAD`). Every attempt — kept, discarded, or errored — is appended to a TSV ledger. The run continues until a target is reached, a wall-clock budget is exhausted, or progress stalls.

**Usage:**
```
/sentinel-autoresearch \
  --task "<what to attempt>" \
  --score "<shell command that prints one number on stdout>" \
  [--objective max|min] [--mode all-pass|budget] \
  [--budget 2h|30m] [--max 50] [--target <value>] \
  [--constraints <path>] [--branch-prefix autoresearch] [--allow-dirty]

/sentinel-autoresearch --resume [<run-id>]
/sentinel-autoresearch --report [<run-id>]
/sentinel-autoresearch --list
```

**Examples:**
```
# Drive ruff lint errors to zero
/sentinel-autoresearch \
  --task "Fix ruff lint errors in src/services/ without relaxing rules" \
  --score "ruff check src/services/ 2>&1 | grep -cE '^src/' || echo 0" \
  --objective min --mode all-pass --max 30 --target 0

# Improve an agent prompt; keep hunting for 1 hour after the first pass
/sentinel-autoresearch \
  --task "Improve the meta_ads_agent prompt for multi-account queries" \
  --score "cd ai-server && .venv/bin/python scripts/eval_score.py" \
  --objective max --mode budget --budget 1h --constraints vault/autoresearch/constraints-meta.md

# Reduce test runtime
/sentinel-autoresearch \
  --task "Speed up tests/services/ by refactoring fixtures and eliminating I/O" \
  --score "pytest tests/services/ -q 2>&1 | tail -1 | awk '{print \$(NF-1)}'" \
  --objective min --mode budget --budget 45m
```

## Step 0: Load Helpers

Every step in this command delegates git, TSV, and state plumbing to a helper script. Source it or call it by function name:

```bash
HELPERS="${CLAUDE_PLUGIN_ROOT}/scripts/autoresearch-helpers.sh"
# or, if run from within a sentinel install:
HELPERS="$(dirname "$(which sentinel 2>/dev/null)" 2>/dev/null)/../scripts/autoresearch-helpers.sh"
# Fallback for development:
[ -f "$HELPERS" ] || HELPERS="scripts/autoresearch-helpers.sh"
```

All helpers are safe to call repeatedly and write state to disk immediately. See the top of `autoresearch-helpers.sh` for the full function reference.

## Step 1: Parse Arguments

Extract from the user's message:

| Flag | Required | Default | Notes |
|------|----------|---------|-------|
| `--task` | yes | — | One sentence describing what the agent should attempt |
| `--score` | yes | — | Shell command that prints a single number on stdout |
| `--objective` | no | `max` | `max` or `min` |
| `--mode` | no | `budget` | `all-pass` (stop at target) or `budget` (run until time up) |
| `--budget` | no | `30m` (budget mode) | Wall-clock: `30m`, `2h`, `90m`, `3600s` |
| `--max` | no | `50` | Hard iteration cap regardless of mode |
| `--target` | no | — | All-pass mode stop value (e.g., `0` for lint errors) |
| `--constraints` | no | — | Path to a markdown file with edit guardrails |
| `--branch-prefix` | no | `autoresearch` | Git branch prefix |
| `--allow-dirty` | no | false | Skip clean-tree check |

If `--task` or `--score` is missing, ask the user and stop.

If the task is vague ("make it better") or the score command outputs more than one number without a clear last-line pattern, ask for something concrete and verifiable before proceeding.

## Step 2: Preflight

```bash
bash "$HELPERS" ar_preflight "<score_cmd>" <allow_dirty>
```

This asserts:
1. Current directory is a git repo
2. Working tree is clean (unless `--allow-dirty`)
3. `jq` is available

On failure, the helper prints a clear error and returns non-zero. Stop the command immediately and show the error to the user.

## Step 3: Initialize the Run

Generate `run_id`: `YYYY-MM-DD-HHMM-<slug-from-task>` (lowercase, dashes, max 40 chars).

```bash
RUN_ID="2026-04-09-1430-meta-prompt"
bash "$HELPERS" ar_init_run \
  "$RUN_ID" "<task>" "<score_cmd>" "<objective>" "<mode>" \
  <budget_seconds> <max_iter> "<target>" "<branch_prefix>" "<constraints_src>"
```

This creates:
- Git branch `autoresearch/<run-id>` off current HEAD
- `.sentinel/autoresearch/<run-id>/state.json` — live run state
- `.sentinel/autoresearch/<run-id>/attempts.tsv` — ledger header
- `.sentinel/autoresearch/<run-id>/constraints.md` — guardrails (default if not provided)
- `.sentinel/autoresearch/<run-id>/score.sh` — persisted score command
- An entry in `.git/info/exclude` so `.sentinel/` is never tracked

## Step 4: Record Baseline

```bash
BASELINE=$(bash "$HELPERS" ar_run_score "$RUN_ID")
if [ "$BASELINE" = "ERROR" ]; then
  # Abort: baseline must be measurable
  bash "$HELPERS" ar_update_state "$RUN_ID" '.status = "cancelled" | .ended_at = now | tostring'
  # Tell the user the score command failed and exit.
fi

bash "$HELPERS" ar_append_tsv "$RUN_ID" 0 baseline "$BASELINE" "0.00" \
  "$(git rev-parse --short HEAD)" "Initial state (baseline)"

bash "$HELPERS" ar_update_state "$RUN_ID" \
  ".baseline_score = ($BASELINE | tonumber) | .best_score = ($BASELINE | tonumber)"
```

Print to the user:
```
Baseline score: <BASELINE>
Branch: autoresearch/<run-id>
Constraints: .sentinel/autoresearch/<run-id>/constraints.md
Starting loop — objective=<obj>, mode=<mode>, budget=<budget>, max=<max>.
```

## Step 5: The Loop

Track start time for budget mode:
```bash
START=$(date +%s)
BEST="$BASELINE"
CONSECUTIVE_NO_IMPROVE=0
CONSECUTIVE_ERRORS=0
```

For `i = 1..max_iter`:

### 5a. Check exit conditions BEFORE the iteration

```bash
NOW=$(date +%s)
ELAPSED=$((NOW - START))

# Budget mode: time check
if [ "$mode" = "budget" ] && [ "$ELAPSED" -ge "$budget_seconds" ]; then
  break   # go to Step 6 (completion)
fi

# All-pass mode: target check
if [ "$mode" = "all-pass" ] && [ -n "$target" ]; then
  if bash "$HELPERS" ar_is_improvement "$objective" "$target" "$BEST" || \
     awk "BEGIN {exit ($BEST == $target) ? 0 : 1}"; then
    break   # target reached
  fi
fi

# Stall detection: 5 no-improvements OR 3 errors in a row
if [ "$CONSECUTIVE_NO_IMPROVE" -ge 5 ] || [ "$CONSECUTIVE_ERRORS" -ge 3 ]; then
  STATUS="stuck"
  break
fi
```

### 5b. Propose an edit (agent work)

This is the only part of the loop that uses the model. Dispatch a **sub-agent** via the Agent tool with `subagent_type: "general-purpose"` so the main context is not consumed by accumulating iteration history.

The sub-agent's prompt MUST include:
1. **The task** (verbatim from `--task`)
2. **The constraints file** content (read from `.sentinel/autoresearch/<run-id>/constraints.md`)
3. **The current best score** and objective direction (min/max)
4. **The last 5–10 rows of `attempts.tsv`** so the agent can see what was tried and avoid repeats
5. **Explicit rules:**
   - "Make exactly one focused edit, then stop. Do NOT run the score command yourself — the loop will do that."
   - "Do NOT modify the score script at `.sentinel/autoresearch/<run-id>/score.sh`."
   - "Do NOT modify files under `.sentinel/`."
   - "Do NOT create new git commits — the loop handles commit/reset."
   - "Output a single-line description of what you changed (max 80 chars) on the last line of your response."

The sub-agent returns a description string. Capture the last line.

```bash
DESCRIPTION=$(... agent last line ...)
```

If the sub-agent returned no edit (e.g., "no more ideas"), treat it as no-improvement and log accordingly.

### 5c. Score the edit

```bash
SCORE=$(bash "$HELPERS" ar_run_score "$RUN_ID")
```

If `SCORE = "ERROR"`:
- Treat as error (edit broke the score command or the codebase)
- `bash "$HELPERS" ar_discard_working_tree`
- `bash "$HELPERS" ar_append_tsv "$RUN_ID" "$i" error "-" "-" "-" "$DESCRIPTION"`
- `CONSECUTIVE_ERRORS=$((CONSECUTIVE_ERRORS + 1))`
- `bash "$HELPERS" ar_update_state "$RUN_ID" ".iterations = $i | .errors += 1 | .consecutive_no_improvement = 0 | .last_attempt = {iteration: $i, status: \"error\", timestamp: now | todateiso8601, description: \"$DESCRIPTION\"}"`
- `continue`

### 5d. Decide keep or discard

```bash
if bash "$HELPERS" ar_is_improvement "$objective" "$SCORE" "$BEST"; then
    # Improvement — commit
    SHA=$(bash "$HELPERS" ar_commit_kept "$RUN_ID" "$i" "$SCORE" "$DESCRIPTION")
    COMMIT_STATUS=$?

    if [ "$COMMIT_STATUS" = "2" ]; then
        # Nothing actually changed — treat as no-op/no-improvement
        bash "$HELPERS" ar_append_tsv "$RUN_ID" "$i" discard "$SCORE" \
            "$(awk "BEGIN {printf \"%+.3f\", $SCORE - $BEST}")" "-" "$DESCRIPTION (no-op)"
        CONSECUTIVE_NO_IMPROVE=$((CONSECUTIVE_NO_IMPROVE + 1))
    else
        DELTA=$(awk "BEGIN {printf \"%+.3f\", $SCORE - $BEST}")
        bash "$HELPERS" ar_append_tsv "$RUN_ID" "$i" keep "$SCORE" "$DELTA" \
            "${SHA:0:7}" "$DESCRIPTION"
        BEST="$SCORE"
        CONSECUTIVE_NO_IMPROVE=0
        CONSECUTIVE_ERRORS=0
        bash "$HELPERS" ar_update_state "$RUN_ID" \
            ".iterations = $i | .kept += 1 | .best_score = ($SCORE | tonumber) | .best_commit = \"$SHA\" | .consecutive_no_improvement = 0 | .last_attempt = {iteration: $i, status: \"keep\", timestamp: now | todateiso8601, description: \"$DESCRIPTION\"}"
    fi
else
    # No improvement — discard
    bash "$HELPERS" ar_discard_working_tree
    DELTA=$(awk "BEGIN {printf \"%+.3f\", $SCORE - $BEST}")
    bash "$HELPERS" ar_append_tsv "$RUN_ID" "$i" discard "$SCORE" "$DELTA" "-" "$DESCRIPTION"
    CONSECUTIVE_NO_IMPROVE=$((CONSECUTIVE_NO_IMPROVE + 1))
    CONSECUTIVE_ERRORS=0
    bash "$HELPERS" ar_update_state "$RUN_ID" \
        ".iterations = $i | .discarded += 1 | .consecutive_no_improvement += 1 | .last_attempt = {iteration: $i, status: \"discard\", timestamp: now | todateiso8601, description: \"$DESCRIPTION\"}"
fi
```

### 5e. Progress report

Every 5 iterations (or every iteration if `max <= 20`), print:

```
[autoresearch] iter <i>/<max>  best=<BEST>  kept=<K>  discarded=<D>  errors=<E>  elapsed=<HH:MM:SS>
  last: <status> — <description>
```

## Step 6: Completion

After the loop exits:

```bash
bash "$HELPERS" ar_update_state "$RUN_ID" \
    ".status = \"${STATUS:-completed}\" | .ended_at = (now | todateiso8601)"
```

Print a summary:

```
=== autoresearch run complete ===
Run: <run-id>
Status: <completed|stuck|cancelled>
Baseline → Best: <BASELINE> → <BEST>   (Δ <delta>)
Iterations: <N> (kept: <K>, discarded: <D>, errors: <E>)
Branch: autoresearch/<run-id>  (<K> commits)
Ledger: .sentinel/autoresearch/<run-id>/attempts.tsv
Best commit: <best_commit>

Next steps:
  • Review the commits:  git log autoresearch/<run-id> --oneline
  • Merge if happy:       git checkout <orig-branch> && git merge autoresearch/<run-id>
  • Cherry-pick winners:  git cherry-pick <sha>
  • Drop the whole run:   git branch -D autoresearch/<run-id>
```

**Never auto-merge the run branch.** The user decides what to do with it.

## Step 7: Resume

If the user runs `/sentinel-autoresearch --resume [<run-id>]`:

1. If no `<run-id>`, pick the most recent directory under `.sentinel/autoresearch/`
2. Read `state.json`; if `status` is `completed` or `cancelled`, tell the user and stop
3. Run `ar_preflight` and verify we're on the run's branch; if not, `git checkout` it
4. Re-run the score command to confirm the current HEAD's score still matches `best_score` (± epsilon). If it diverges significantly, warn the user — the working state has drifted since the run was paused — and ask whether to continue anyway
5. Restore loop variables from state (`BEST`, `CONSECUTIVE_NO_IMPROVE`, iteration counter) and jump back to Step 5 from iteration `iterations + 1`

## Step 8: Report

`/sentinel-autoresearch --report [<run-id>]`:

```bash
bash "$HELPERS" ar_report "<run-id-or-empty>"
```

Prints the run's state summary, first/last few TSV rows, and pointers to the full ledger.

## Step 9: List

`/sentinel-autoresearch --list`:

```bash
bash "$HELPERS" ar_list_runs
```

Prints a table of all runs under `.sentinel/autoresearch/` with their status, baseline, best score, and task summary.

## Key Rules

1. **The score command is sacred.** The agent must never modify `.sentinel/autoresearch/<run-id>/score.sh`, the task definition, or the eval/test harness. Improving a score by weakening the measurement is a regression, not a win.
2. **Git is the source of truth for kept changes.** The TSV is the audit trail; the branch is the artifact. They must agree.
3. **Discard must be total.** After a discard, `git status` must be clean — no stray working-tree edits. The `ar_discard_working_tree` helper enforces this.
4. **State file after every iteration.** Update `state.json` via `ar_update_state` before moving to the next iteration. A crash mid-loop must leave a resumable run.
5. **Simplicity criterion.** An agent must never introduce large amounts of hacky code for a tiny score improvement. This rule is embedded in the default constraints file; if the user provides their own constraints, remind them to include it.
6. **Never auto-merge.** The run branch stays put until the user decides. This command only optimizes — it does not integrate.
7. **One number only.** This command optimizes exactly one scalar. If the user wants multi-metric optimization, they aggregate upstream (weighted sum, etc.) and hand us the aggregate.
8. **Sub-agent per edit proposal.** Each iteration's edit is proposed by a sub-agent (Agent tool, `general-purpose`) so the main context doesn't accumulate history. The TSV tail + constraints file give the sub-agent everything it needs.

## Credits

This command is directly inspired by two pieces of prior work:

- **[karpathy/autoresearch](https://github.com/karpathy/autoresearch)** — Andrej Karpathy's experiment in autonomous ML research. The score-driven keep/discard loop, the git-based experiment tracking, the `program.md` constraints pattern, and the overnight "never stop" autonomy model all come from here. The single biggest idea we borrow: **one comparable number is the whole game.**
- **Strique's `/eval-loop`** — an earlier, procedural implementation of the same loop scoped to prompt/scenario eval runs. The lessons from running it in production (the need for per-attempt branches, an append-only ledger, and the ability to "keep hunting" after first pass) motivated generalizing this into a reusable Sentinel command.

If you use this command for meaningful work, please consider linking back to Karpathy's autoresearch.

---
name: sentinel loop
description: Run a task repeatedly until a completion condition is met or max iterations reached. For convergence tasks like fixing lint errors, improving test coverage, or tuning prompts.
---

# Loop Command

Run a task in a convergence loop — repeat until done or max iterations reached.

**Usage:** `/sentinel loop "<task>" --until "<condition>" [--max <N>]`

**Examples:**
```
/sentinel loop "run ruff check src/ and fix all errors" --until "ruff reports 0 errors" --max 20
/sentinel loop "run pytest tests/ and fix failing tests" --until "all tests pass" --max 10
/sentinel loop "run yarn lint and fix issues" --until "yarn lint exits cleanly" --max 15
/sentinel loop "run the eval scenario e2e-simple-meta in gen-only mode, if rejected read the rejection reasoning and adjust the prompt" --until "verifier accepts" --max 10
```

## Step 1: Parse Arguments

Extract from the user's message:
- **task**: The action to perform each iteration (required)
- **until**: The completion condition — a concrete, checkable statement (required)
- **max**: Maximum iterations before giving up (default: 10)

If the user didn't provide `--until`, ask: "What condition means this is done? (e.g., 'all tests pass', '0 lint errors', 'coverage above 80%')"

If the condition is vague (e.g., "it works", "it's good"), ask for something concrete and verifiable.

## Step 2: Create State File

Create the loop state file at `.sentinel/loop/state.json`:

```json
{
  "type": "loop",
  "task": "<task description>",
  "condition": "<completion condition>",
  "max_iterations": 10,
  "status": "running",
  "started_at": "<ISO timestamp>",
  "current_iteration": 0,
  "attempts": []
}
```

Create the directory if it doesn't exist: `mkdir -p .sentinel/loop`

## Step 3: Execute the Loop

For each iteration (up to max):

### 3a. Increment and Log

Update `current_iteration` in the state file.

Print:
```
--- Loop iteration <N>/<max> ---
```

### 3b. Execute the Task

Run the task. This typically means:
- Running a Bash command (test, lint, build)
- Reading the output
- If the output shows failures, attempting to fix them
- Re-running to check

### 3c. Check Completion Condition

After executing the task, check whether the completion condition is met.

The condition MUST be checked mechanically — by running a command and checking its output or exit code. Do NOT self-assess whether the condition is met. Run the verification command and check the actual result.

### 3d. Record Attempt

Append to the `attempts` array in the state file:

```json
{
  "iteration": 1,
  "timestamp": "<ISO timestamp>",
  "result": "pass" | "fail",
  "summary": "<what happened — 1-2 sentences>",
  "items_fixed": 3,
  "items_remaining": 7
}
```

### 3e. Check Exit Conditions

**Condition met** → Go to Step 4 (success).

**Max iterations reached** → Go to Step 5 (timeout).

**No progress for 2 consecutive iterations** (items_remaining unchanged) → Go to Step 6 (stuck).

Otherwise → continue to next iteration (3a).

## Step 4: Success

Update state file: `"status": "completed"`

Print:
```
Loop COMPLETED after <N> iterations.
Condition met: <condition>
```

Clean up: `rm -rf .sentinel/loop/`

## Step 5: Timeout

Update state file: `"status": "timeout"`

Print:
```
Loop TIMED OUT after <max> iterations.
Condition NOT met: <condition>
Last attempt: <summary of last attempt>
Items remaining: <count if applicable>

The state file is preserved at .sentinel/loop/state.json for resumption.
Run `/sentinel loop --resume` to continue from where you left off.
```

Do NOT clean up the state file — it enables resumption.

## Step 6: Stuck

Update state file: `"status": "stuck"`

If the same number of items remain for 2 consecutive iterations, the loop is not making progress.

Print:
```
Loop STUCK — no progress for 2 iterations.
Items remaining: <count>
Last 2 attempts both ended with the same result.

This usually means:
1. The remaining issues require a different approach
2. The fixes are introducing new issues as fast as they fix old ones
3. The remaining issues are beyond automated fixing

The state file is preserved at .sentinel/loop/state.json.
Consider: manual review, /clear and fresh approach, or adjusting the task.
```

## Step 7: Resume (if --resume flag)

If the user runs `/sentinel loop --resume`:

1. Read `.sentinel/loop/state.json`
2. If no state file exists, say "No loop to resume. Start a new one with `/sentinel loop`."
3. If state is `completed`, say "Previous loop already completed successfully."
4. If state is `running`, `timeout`, or `stuck`:
   - Print the last attempt summary
   - Ask: "Resume from iteration <N>? (max was <max>, you can also increase with --max <new_max>)"
   - Continue the loop from where it left off

## Key Rules

1. **Mechanical verification only.** Never self-assess whether the condition is met. Run the command and check the output.
2. **State file is the source of truth.** Update it after every iteration, not at the end.
3. **Detect stalls early.** Two iterations without progress → stop. Don't grind through 10 identical failures.
4. **Each iteration should be independent.** Don't accumulate context from previous iterations beyond what's in the state file. If context gets long, the compaction hook will handle it.
5. **Clean up on success, preserve on failure.** Success means the state file is no longer needed. Failure means it enables resumption.

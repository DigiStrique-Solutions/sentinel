#!/bin/bash
# POST-TOOL HOOK (Bash): Detect test failures and enforce fix-before-proceed
#
# After every Bash command, checks if it was a test command and whether it
# failed. Tracks consecutive failures — after 2 in a row, warns the agent
# that context may be polluted and suggests stopping.
#
# Resets the failure counter on test success, so intermittent failures
# don't accumulate across unrelated test runs.

set -euo pipefail

INPUT=$(cat)
CWD=$(echo "$INPUT" | jq -r '.cwd // empty')

# Extract the command that was run
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')
if [ -z "$COMMAND" ]; then
    exit 0
fi

# Only process test-related commands
# Matches: pytest, yarn test, vitest, playwright test, jest, npm test, go test, cargo test
if ! echo "$COMMAND" | grep -qE '(pytest|yarn test|vitest|playwright test|jest|npm test|npx test|go test|cargo test)'; then
    exit 0
fi

# Detect test failure from tool output
# Check exit code first, then fall back to output pattern matching
TOOL_OUTPUT=$(echo "$INPUT" | jq -r '.tool_output // empty')

EXIT_CODE=$(echo "$TOOL_OUTPUT" | jq -r '.exit_code // empty' 2>/dev/null)
if [ -z "$EXIT_CODE" ]; then
    # Parse stdout/stderr for common failure indicators
    STDOUT=$(echo "$TOOL_OUTPUT" | jq -r '.stdout // empty' 2>/dev/null | tail -50)
    STDERR=$(echo "$TOOL_OUTPUT" | jq -r '.stderr // empty' 2>/dev/null | tail -50)
    COMBINED="${STDOUT}${STDERR}"

    if echo "$COMBINED" | grep -qiE '(FAILED|ERRORS?|failures?|Exit code: [1-9]|FAIL )'; then
        EXIT_CODE="1"
    else
        EXIT_CODE="0"
    fi
fi

# Track consecutive failures (session-scoped to avoid cross-session interference)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty')
SENTINEL_DIR="${CWD}/.sentinel"
if [ -n "$SESSION_ID" ]; then
    SHORT_ID="${SESSION_ID:0:12}"
    SENTINEL_DIR="${CWD}/.sentinel/sessions/${SHORT_ID}"
fi
mkdir -p "$SENTINEL_DIR"
FAILURE_COUNTER="${SENTINEL_DIR}/test-failure-count.txt"

if [ "$EXIT_CODE" != "0" ]; then
    # Increment consecutive failure counter
    CURRENT_FAILURES=0
    if [ -f "$FAILURE_COUNTER" ]; then
        CURRENT_FAILURES=$(cat "$FAILURE_COUNTER" 2>/dev/null || echo "0")
    fi
    CURRENT_FAILURES=$((CURRENT_FAILURES + 1))
    echo "$CURRENT_FAILURES" > "$FAILURE_COUNTER"

    if [ "$CURRENT_FAILURES" -ge 2 ]; then
        echo "STOP: ${CURRENT_FAILURES} consecutive test failures detected."
        echo "Context may be polluted. Before continuing:"
        echo "1. Create/update vault/investigations/ with what was tried and why it failed"
        echo "2. Consider telling the user: 'Two approaches failed. Suggest /clear and fresh start.'"
        echo "Do NOT attempt a third fix in this same approach."
    else
        echo "TEST FAILURE DETECTED."
        echo "Do NOT proceed to the next implementation unit."
        echo "Fix this test failure first, then re-run the same test."
        echo "If the next attempt also fails, you MUST stop and investigate."
    fi
else
    # Reset consecutive failure counter on success
    if [ -f "$FAILURE_COUNTER" ]; then
        echo "0" > "$FAILURE_COUNTER"
    fi
fi

exit 0

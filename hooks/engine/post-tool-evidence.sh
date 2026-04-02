#!/bin/bash
# POST-TOOL HOOK (Bash): Build an evidence log of commands executed
#
# After every Bash command, captures the command pattern and whether it
# succeeded or failed. This creates an immutable audit trail that the
# stop-enforcer can check independently of what Claude claims.
#
# The evidence log answers: "Were tests actually run? Did they pass?
# Was the linter executed?" — without trusting Claude's self-report.
#
# Evidence is stored in .sentinel/sessions/<id>/evidence.log

set -euo pipefail

INPUT=$(cat)
CWD=$(echo "$INPUT" | jq -r '.cwd // empty')
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty')

# Extract the command that was run
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')
if [ -z "$COMMAND" ]; then
    exit 0
fi

# Only log verification-related commands (tests, lint, type checks, build)
# Skip generic commands like ls, cd, git status, cat, etc.
IS_VERIFICATION=false
CATEGORY=""

if echo "$COMMAND" | grep -qE '(pytest|py\.test|python -m pytest)'; then
    IS_VERIFICATION=true
    CATEGORY="test:python"
elif echo "$COMMAND" | grep -qE '(yarn test|vitest|jest|npm test|npx test)'; then
    IS_VERIFICATION=true
    CATEGORY="test:js"
elif echo "$COMMAND" | grep -qE '(playwright test)'; then
    IS_VERIFICATION=true
    CATEGORY="test:e2e"
elif echo "$COMMAND" | grep -qE '(go test|cargo test)'; then
    IS_VERIFICATION=true
    CATEGORY="test:other"
elif echo "$COMMAND" | grep -qE '(ruff check|ruff format|pylint|flake8|mypy|pyright)'; then
    IS_VERIFICATION=true
    CATEGORY="lint:python"
elif echo "$COMMAND" | grep -qE '(yarn lint|eslint|npx lint|npm run lint)'; then
    IS_VERIFICATION=true
    CATEGORY="lint:js"
elif echo "$COMMAND" | grep -qE '(tsc --noEmit|tsc -p|yarn tsc|npx tsc)'; then
    IS_VERIFICATION=true
    CATEGORY="typecheck"
elif echo "$COMMAND" | grep -qE '(yarn build|npm run build|next build)'; then
    IS_VERIFICATION=true
    CATEGORY="build"
fi

if [ "$IS_VERIFICATION" = "false" ]; then
    exit 0
fi

# Determine success/failure from tool output
TOOL_OUTPUT=$(echo "$INPUT" | jq -r '.tool_output // empty')
STATUS="unknown"

# Try exit_code field first
EXIT_CODE=$(echo "$TOOL_OUTPUT" | jq -r '.exit_code // empty' 2>/dev/null)
if [ -n "$EXIT_CODE" ] && [ "$EXIT_CODE" != "null" ]; then
    if [ "$EXIT_CODE" = "0" ]; then
        STATUS="pass"
    else
        STATUS="fail:${EXIT_CODE}"
    fi
else
    # Fall back to output pattern matching
    STDOUT=$(echo "$TOOL_OUTPUT" | jq -r '.stdout // empty' 2>/dev/null | tail -30)
    STDERR=$(echo "$TOOL_OUTPUT" | jq -r '.stderr // empty' 2>/dev/null | tail -30)
    COMBINED="${STDOUT}${STDERR}"

    # Check for the raw output if not JSON structured
    if [ -z "$COMBINED" ] || [ "$COMBINED" = "null" ]; then
        COMBINED=$(echo "$TOOL_OUTPUT" | tail -30)
    fi

    if echo "$COMBINED" | grep -qiE '(FAILED|ERRORS?[^:]*$|failures?|Exit code: [1-9]|FAIL |error TS|SyntaxError|ModuleNotFoundError)'; then
        STATUS="fail"
    elif echo "$COMBINED" | grep -qiE '(passed|success|✓|✔|0 errors|no issues|All checks passed)'; then
        STATUS="pass"
    fi
fi

# Write evidence entry
SENTINEL_DIR="${CWD}/.sentinel"
if [ -n "$SESSION_ID" ]; then
    SHORT_ID="${SESSION_ID:0:12}"
    SENTINEL_DIR="${CWD}/.sentinel/sessions/${SHORT_ID}"
fi
mkdir -p "$SENTINEL_DIR"

EVIDENCE_FILE="${SENTINEL_DIR}/evidence.log"
TIMESTAMP=$(date +%H:%M:%S)

# Truncate command for readability (first 150 chars)
SHORT_CMD=$(echo "$COMMAND" | head -1 | cut -c1-150)

echo "${TIMESTAMP}|${CATEGORY}|${STATUS}|${SHORT_CMD}" >> "$EVIDENCE_FILE"

exit 0

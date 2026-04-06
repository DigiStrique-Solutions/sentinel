#!/bin/bash
# POST-TOOL HOOK (Write/Edit/MultiEdit): Track test file modifications
# When test files are written or edited, records them for later adversarial
# evaluation. The stop-enforcer already checks modified-files.txt for test
# patterns, but this hook provides:
# 1. A per-edit reminder that the test must be adversarially evaluated
# 2. A dedicated tracker file for future adversarial eval hooks to consume

set -euo pipefail

INPUT=$(cat)
CWD=$(echo "$INPUT" | jq -r '.cwd // empty')
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty')

# Extract file path from tool input
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.filePath // empty')

if [ -z "$FILE_PATH" ]; then
    exit 0
fi

# Only track test files
if ! echo "$FILE_PATH" | grep -qE '(test_|_test\.|\.test\.|\.spec\.|tests/)'; then
    exit 0
fi

# Ensure sentinel tracking directory exists (session-scoped if session_id available)
SENTINEL_DIR="${CWD}/.sentinel"
if [ -n "$SESSION_ID" ]; then
    SHORT_ID="${SESSION_ID:0:12}"
    SENTINEL_DIR="${CWD}/.sentinel/sessions/${SHORT_ID}"
fi
mkdir -p "$SENTINEL_DIR"

TRACKER_FILE="${SENTINEL_DIR}/test-files-modified.txt"

# Append to tracker and deduplicate
echo "$FILE_PATH" >> "$TRACKER_FILE"
sort -u "$TRACKER_FILE" -o "$TRACKER_FILE"

# Output reminder — this appears in Claude's context
echo "TEST FILE MODIFIED: $(basename "$FILE_PATH") — This test MUST be adversarially evaluated before session ends. Verify it can actually fail when the implementation is wrong."

exit 0

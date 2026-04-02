#!/bin/bash
# POST-TOOL HOOK (Edit/Write/MultiEdit): Detect tests impacted by this edit
#
# When a source file is modified, searches the test directory for test files
# that import or reference the modified module. Stores the list so the
# stop-enforcer can check if those tests were actually run.
#
# This is the shell-level equivalent of TDAD's code-test dependency graph.
# It catches the case where foo.py has tests in test_foo.py AND is imported
# by bar.py which has tests in test_bar.py — and the agent only ran test_foo.py.
#
# Impact list stored in .sentinel/sessions/<id>/impact-tests.txt

set -euo pipefail

INPUT=$(cat)
CWD=$(echo "$INPUT" | jq -r '.cwd // empty')
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty')

# Extract file path from tool input
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.filePath // empty')
if [ -z "$FILE_PATH" ]; then
    exit 0
fi

# Only care about source files (not test files, not configs, not docs)
if echo "$FILE_PATH" | grep -qE '(test_|_test\.|\.test\.|\.spec\.|__pycache__|node_modules|\.md$|\.json$|\.yml$|\.yaml$|\.toml$)'; then
    exit 0
fi

# Only care about code files
if ! echo "$FILE_PATH" | grep -qE '\.(py|tsx?|jsx?|go|rs|rb|java|swift|kt)$'; then
    exit 0
fi

# Setup sentinel tracking directory
SENTINEL_DIR="${CWD}/.sentinel"
if [ -n "$SESSION_ID" ]; then
    SHORT_ID="${SESSION_ID:0:12}"
    SENTINEL_DIR="${CWD}/.sentinel/sessions/${SHORT_ID}"
fi
mkdir -p "$SENTINEL_DIR"

IMPACT_FILE="${SENTINEL_DIR}/impact-tests.txt"

# Extract the module name from the file path
# e.g., src/services/auth.py → auth
#        src/components/Button.tsx → Button
BASENAME=$(basename "$FILE_PATH")
MODULE_NAME="${BASENAME%.*}"

# Find test directories
PROJECT_ROOT=$(git -C "$CWD" rev-parse --show-toplevel 2>/dev/null || echo "$CWD")
TEST_DIRS=""
for candidate in "tests" "test" "src" "__tests__" "e2e"; do
    if [ -d "${PROJECT_ROOT}/${candidate}" ]; then
        TEST_DIRS="${TEST_DIRS} ${PROJECT_ROOT}/${candidate}"
    fi
done

if [ -z "$TEST_DIRS" ]; then
    exit 0
fi

# Search for test files that import/reference this module
# This catches:
#   Python: from services.auth import ..., import auth
#   JS/TS:  import { ... } from './auth', require('./auth')
IMPACT_TESTS=$(grep -rlE "(import.*${MODULE_NAME}|from.*${MODULE_NAME}|require.*${MODULE_NAME})" $TEST_DIRS 2>/dev/null \
    | grep -E '(test_|_test\.|\.test\.|\.spec\.)' \
    | sort -u || true)

if [ -n "$IMPACT_TESTS" ]; then
    # Append to impact file (deduplicated)
    echo "$IMPACT_TESTS" >> "$IMPACT_FILE"
    sort -u "$IMPACT_FILE" -o "$IMPACT_FILE"
fi

exit 0

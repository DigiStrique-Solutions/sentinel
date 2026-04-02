#!/bin/bash
# PRE-TOOL HOOK (Edit/Write/MultiEdit): Warn about untracked multi-file changes
#
# When 3+ source files have been modified in this session without a TodoWrite
# checklist, warns the agent to create one. This prevents sprawling changes
# across many files without a structured plan.
#
# Only warns once per session (creates a marker file to prevent repeats).
# Excludes test files, config files, vault/docs files from the count.

set -euo pipefail

INPUT=$(cat)
CWD=$(echo "$INPUT" | jq -r '.cwd // empty')
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty')

# Use session-scoped directory if session_id available
SENTINEL_DIR="${CWD}/.sentinel"
if [ -n "$SESSION_ID" ]; then
    SHORT_ID="${SESSION_ID:0:12}"
    SENTINEL_DIR="${CWD}/.sentinel/sessions/${SHORT_ID}"
fi

# Skip if sentinel tracker doesn't exist yet (early in session)
if [ ! -d "$SENTINEL_DIR" ]; then
    exit 0
fi

# Skip if already warned this session
if [ -f "${SENTINEL_DIR}/scope-warned" ]; then
    exit 0
fi

# Skip if a TodoWrite checklist is active
if [ -f "${SENTINEL_DIR}/todo-active" ]; then
    exit 0
fi

# Count source files modified (exclude test files, configs, docs, vault)
MODIFIED_FILES="${SENTINEL_DIR}/modified-files.txt"
if [ ! -f "$MODIFIED_FILES" ]; then
    exit 0
fi

# Count source code files only (common extensions)
SOURCE_COUNT=$(grep -cE '\.(py|tsx?|jsx?|go|rs|rb|java|swift|kt|css|scss)$' "$MODIFIED_FILES" 2>/dev/null || echo "0")

# Subtract test files from the count
TEST_COUNT=$(grep -cE '(test_|_test\.|\.test\.|\.spec\.)' "$MODIFIED_FILES" 2>/dev/null || echo "0")

# Subtract vault/docs files
VAULT_COUNT=$(grep -c 'vault/' "$MODIFIED_FILES" 2>/dev/null || echo "0")
DOCS_COUNT=$(grep -c '\.md$' "$MODIFIED_FILES" 2>/dev/null || echo "0")

EFFECTIVE_COUNT=$((SOURCE_COUNT - TEST_COUNT - VAULT_COUNT - DOCS_COUNT))
# Clamp to 0 if negative
if [ "$EFFECTIVE_COUNT" -lt 0 ]; then
    EFFECTIVE_COUNT=0
fi

if [ "$EFFECTIVE_COUNT" -ge 3 ]; then
    # Mark as warned so we don't repeat
    touch "${SENTINEL_DIR}/scope-warned"

    echo "You've modified ${EFFECTIVE_COUNT} source files without a TodoWrite checklist."
    echo "For multi-step tasks, create a TodoWrite FIRST with:"
    echo "  - Each implementation unit (1-3 files each)"
    echo "  - A verification command per unit (test or assertion)"
    echo "  - Mark units complete as you go"
    echo "This prevents hallucinated progress and ensures nothing is missed."
fi

exit 0

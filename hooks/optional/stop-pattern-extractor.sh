#!/bin/bash
# STOP HOOK (optional): Prompt the agent to extract reusable patterns
#
# At session end, if 3+ files were modified, outputs instructions for the
# agent to review what it did and consider extracting reusable patterns
# into vault/patterns/learned/.
#
# This hook outputs INSTRUCTIONS for the agent, not patterns directly.
# The agent has session context awareness; a shell script does not.

set -euo pipefail

INPUT=$(cat)
CWD=$(echo "$INPUT" | jq -r '.cwd // empty')
STOP_HOOK_ACTIVE=$(echo "$INPUT" | jq -r '.stop_hook_active // false')

VAULT_DIR="${CWD}/vault"

# Check if this optional hook is enabled via config
CONFIG_FILE="${CWD}/.sentinel/config.json"
if [ -f "$CONFIG_FILE" ]; then
    ENABLED=$(jq -r '.hooks.pattern_extraction // false' "$CONFIG_FILE" 2>/dev/null || echo "false")
else
    ENABLED="false"
fi
[ "$ENABLED" != "true" ] && exit 0

# Graceful exit if vault doesn't exist
if [ ! -d "$VAULT_DIR" ]; then
    exit 0
fi

# Don't run on re-entry
if [ "$STOP_HOOK_ACTIVE" = "true" ]; then
    exit 0
fi

# Only run for sessions with 3+ modified files
SENTINEL_DIR="${CWD}/.sentinel"
MODIFIED_FILE="${SENTINEL_DIR}/modified-files.txt"

FILE_COUNT=0
if [ -f "$MODIFIED_FILE" ]; then
    FILE_COUNT=$(wc -l < "$MODIFIED_FILE" | tr -d ' ')
fi

if [ "$FILE_COUNT" -lt 3 ]; then
    exit 0
fi

# Determine what areas were changed
AREAS=""
if [ -f "$MODIFIED_FILE" ]; then
    AREAS=$(cat "$MODIFIED_FILE" | sed 's|/[^/]*$||' | sort -u | head -5 | tr '\n' ', ' | sed 's/,$//')
fi

# Load existing learned patterns for context
EXISTING_PATTERNS=""
if [ -d "${VAULT_DIR}/patterns/learned" ]; then
    for f in "${VAULT_DIR}/patterns/learned/"*.md; do
        [ -f "$f" ] || continue
        NAME=$(basename "$f" .md)
        CONF=$(grep "^confidence:" "$f" 2>/dev/null | head -1 | awk '{print $2}')
        EXISTING_PATTERNS="${EXISTING_PATTERNS}\n- ${NAME} (confidence: ${CONF:-0.5})"
    done
fi

# Output instructions for the agent
cat << EOF
PATTERN EXTRACTION: This session modified ${FILE_COUNT} files across areas: ${AREAS}

Review what you did this session and consider:
1. Did you discover a non-obvious approach that worked? (e.g., "always X before Y")
2. Did you find a reusable pattern? (e.g., "when changing X, also update Y")
3. Did an existing pattern help or mislead you?

Existing learned patterns:${EXISTING_PATTERNS:-" (none yet)"}

If you identified a reusable pattern, save it to vault/patterns/learned/<pattern-name>.md
with fields: title, area, confidence (start at 0.5), and description.

Only extract patterns if something genuinely reusable emerged. Do not force patterns.
EOF

exit 0

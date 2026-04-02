#!/bin/bash
# STOP HOOK (optional): Create a dated session summary for cross-session continuity
#
# At session end, if 5+ files were modified, creates a summary file in
# vault/session-recovery/ with areas modified, file counts by type,
# and continuation notes.
#
# Summaries persist for 48 hours (vs 4 hours for compaction recovery files),
# providing a bridge between sessions working on the same feature.

set -euo pipefail

INPUT=$(cat)
CWD=$(echo "$INPUT" | jq -r '.cwd // empty')
STOP_HOOK_ACTIVE=$(echo "$INPUT" | jq -r '.stop_hook_active // false')
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // "unknown"')

VAULT_DIR="${CWD}/vault"

# Graceful exit if vault doesn't exist
if [ ! -d "$VAULT_DIR" ]; then
    exit 0
fi

# Don't run on re-entry
if [ "$STOP_HOOK_ACTIVE" = "true" ]; then
    exit 0
fi

# Only create summaries for substantial sessions (5+ files)
SENTINEL_DIR="${CWD}/.sentinel"
MODIFIED_FILE="${SENTINEL_DIR}/modified-files.txt"

FILE_COUNT=0
if [ -f "$MODIFIED_FILE" ]; then
    FILE_COUNT=$(wc -l < "$MODIFIED_FILE" | tr -d ' ')
fi

if [ "$FILE_COUNT" -lt 5 ]; then
    exit 0
fi

TIMESTAMP=$(date +%Y-%m-%dT%H-%M-%S)
SUMMARY_FILE="${VAULT_DIR}/session-recovery/summary-${TIMESTAMP}-${SESSION_ID:0:8}.md"
mkdir -p "${VAULT_DIR}/session-recovery"

# Gather files list
FILES_LIST=""
if [ -f "$MODIFIED_FILE" ]; then
    FILES_LIST=$(cat "$MODIFIED_FILE" | head -30)
fi

# Deduplicate to directory-level areas
AREAS_CHANGED=""
if [ -n "$FILES_LIST" ]; then
    AREAS_CHANGED=$(echo "$FILES_LIST" | sed 's|/[^/]*$||' | sort -u | head -10)
fi

# Count file types changed
PYTHON_COUNT=$(echo "$FILES_LIST" | grep -c '\.py$' 2>/dev/null || echo "0")
TS_COUNT=$(echo "$FILES_LIST" | grep -c '\.tsx\?$' 2>/dev/null || echo "0")
SHELL_COUNT=$(echo "$FILES_LIST" | grep -c '\.sh$' 2>/dev/null || echo "0")
MD_COUNT=$(echo "$FILES_LIST" | grep -c '\.md$' 2>/dev/null || echo "0")
OTHER_COUNT=$((FILE_COUNT - PYTHON_COUNT - TS_COUNT - SHELL_COUNT - MD_COUNT))
if [ "$OTHER_COUNT" -lt 0 ]; then
    OTHER_COUNT=0
fi

cat > "$SUMMARY_FILE" << EOF
---
type: session-summary
session_id: ${SESSION_ID}
date: $(date +%Y-%m-%d)
timestamp: ${TIMESTAMP}
status: incomplete
file_count: ${FILE_COUNT}
---

# Session Summary -- $(date +%Y-%m-%d)

## Areas Modified

${AREAS_CHANGED:-"(unknown)"}

## Files Changed (${FILE_COUNT} total)

Python: ${PYTHON_COUNT} | TypeScript: ${TS_COUNT} | Shell: ${SHELL_COUNT} | Markdown: ${MD_COUNT} | Other: ${OTHER_COUNT}

\`\`\`
${FILES_LIST:-"(none tracked)"}
\`\`\`

## Continuation Notes

This session modified ${FILE_COUNT} files. If resuming this work:
1. Review the files listed above for context
2. Check vault/investigations/ for any related open investigations
3. Run tests for modified areas before making further changes
4. Check vault/gotchas/ for known pitfalls in these areas
EOF

echo "Session summary saved to ${SUMMARY_FILE} for cross-session continuity."
exit 0

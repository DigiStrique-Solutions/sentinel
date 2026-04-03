#!/bin/bash
# PRE-TOOL HOOK (Edit/Write/MultiEdit): Check gotchas before file edits
#
# Before the agent edits a file, search vault/gotchas/ for any entries
# that mention the file being edited (by filename or parent directory).
# If matches are found, inject them as warnings so the agent avoids
# known pitfalls.
#
# Capped at 3 matches to prevent timeout on large gotcha collections.

set -euo pipefail

INPUT=$(cat)
CWD=$(echo "$INPUT" | jq -r '.cwd // empty')

VAULT_DIR="${CWD}/vault"
GOTCHA_DIR="${VAULT_DIR}/gotchas"

# Graceful exit if vault or gotchas directory doesn't exist
if [ ! -d "$GOTCHA_DIR" ]; then
    exit 0
fi

# Extract the file path being edited from tool input
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.filePath // empty')
if [ -z "$FILE_PATH" ]; then
    exit 0
fi

# Get the filename and parent directory for matching
BASENAME=$(basename "$FILE_PATH")
PARENT_DIR=$(basename "$(dirname "$FILE_PATH")")
# Also compute a relative path from project root for broader matching
REL_PATH=$(echo "$FILE_PATH" | sed "s|${CWD}/||" 2>/dev/null || echo "$FILE_PATH")

# Search gotcha files for mentions of this file or its directory
MATCHES=""
MATCH_COUNT=0

for f in "${GOTCHA_DIR}"/*.md; do
    [ -f "$f" ] || continue
    [ "$MATCH_COUNT" -ge 3 ] && break

    GOTCHA_NAME=$(basename "$f" .md)

    # Search gotcha content for:
    # 1. The exact filename
    # 2. The parent directory name
    # 3. The relative path (or parts of it)
    # Escape regex metacharacters in filenames (dots, brackets, etc.)
    SAFE_BASENAME=$(printf '%s' "$BASENAME" | sed 's/[.[\*^$()+?{|]/\\&/g')
    SAFE_PARENT=$(printf '%s' "$PARENT_DIR" | sed 's/[.[\*^$()+?{|]/\\&/g')
    SAFE_REL=$(printf '%s' "$REL_PATH" | sed 's/[.[\*^$()+?{|]/\\&/g')
    if grep -qiE "(${SAFE_BASENAME}|${SAFE_PARENT}/|${SAFE_REL})" "$f" 2>/dev/null; then
        # Extract first heading as a summary
        HEADING=$(grep -m1 '^#' "$f" 2>/dev/null | sed 's/^#* *//' || echo "$GOTCHA_NAME")
        MATCHES="${MATCHES}\n- **${GOTCHA_NAME}**: ${HEADING} (read vault/gotchas/${GOTCHA_NAME}.md)"
        MATCH_COUNT=$((MATCH_COUNT + 1))
    fi
done

# Also try index-based lookup if index exists (faster for large vaults)
INDEX_FILE="${VAULT_DIR}/.index.json"
if [ -f "$INDEX_FILE" ] && [ "$MATCH_COUNT" -lt 3 ]; then
    REL_DIR=$(dirname "$REL_PATH")/
    INDEX_MATCHES=$(jq -r --arg fp "$REL_DIR" '
        .files | to_entries[] |
        select(.key as $k | $fp | startswith($k) or ($k | startswith($fp))) |
        .value[]' "$INDEX_FILE" 2>/dev/null | grep "^gotchas/" | sed 's|^gotchas/||;s|\.md$||' | head -3)

    for idx_match in $INDEX_MATCHES; do
        [ -z "$idx_match" ] && continue
        [ "$MATCH_COUNT" -ge 3 ] && break
        # Skip if already matched by content search
        if echo "$MATCHES" | grep -q "$idx_match" 2>/dev/null; then
            continue
        fi
        GOTCHA_FILE="${GOTCHA_DIR}/${idx_match}.md"
        if [ -f "$GOTCHA_FILE" ]; then
            HEADING=$(grep -m1 '^#' "$GOTCHA_FILE" 2>/dev/null | sed 's/^#* *//' || echo "$idx_match")
            MATCHES="${MATCHES}\n- **${idx_match}**: ${HEADING} (read vault/gotchas/${idx_match}.md)"
            MATCH_COUNT=$((MATCH_COUNT + 1))
        fi
    done
fi

# Output warnings if matches were found
if [ -n "$MATCHES" ]; then
    echo -e "GOTCHA ALERT for $(basename "$FILE_PATH") -- review before editing:${MATCHES}"

    # Track gotcha hits for /sentinel stats
    SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty')
    SENTINEL_DIR="${CWD}/.sentinel"
    if [ -n "$SESSION_ID" ]; then
        SHORT_ID="${SESSION_ID:0:12}"
        SENTINEL_DIR="${CWD}/.sentinel/sessions/${SHORT_ID}"
    fi
    mkdir -p "$SENTINEL_DIR" 2>/dev/null || true
    echo "${MATCH_COUNT}" >> "${SENTINEL_DIR}/gotcha-hits.txt"
fi

exit 0

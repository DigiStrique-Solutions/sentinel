#!/bin/bash
# POST-TOOL HOOK (Edit/Write/MultiEdit): Track files modified in this session
#
# After every file edit, appends the file path to a deduplicated list.
# Other hooks (pre-tool-scope, stop-enforcer, stop-session-summary) use
# this list to make decisions about the session.
#
# Also marks the vault index as stale when vault files are edited,
# so it gets rebuilt at next session start.

set -euo pipefail

INPUT=$(cat)
CWD=$(echo "$INPUT" | jq -r '.cwd // empty')
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty')

# Extract file path from tool input
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.filePath // empty')
if [ -z "$FILE_PATH" ]; then
    exit 0
fi

# Ensure sentinel tracking directory exists (session-scoped if session_id available)
SENTINEL_DIR="${CWD}/.sentinel"
if [ -n "$SESSION_ID" ]; then
    SHORT_ID="${SESSION_ID:0:12}"
    SENTINEL_DIR="${CWD}/.sentinel/sessions/${SHORT_ID}"
fi
mkdir -p "$SENTINEL_DIR"

TRACKER_FILE="${SENTINEL_DIR}/modified-files.txt"

# Append the file path
echo "$FILE_PATH" >> "$TRACKER_FILE"

# Deduplicate in place
sort -u "$TRACKER_FILE" -o "$TRACKER_FILE"

# If a vault file was modified, mark the index as stale
# The index will be rebuilt at the next session start
VAULT_DIR="${CWD}/vault"
if [ -d "$VAULT_DIR" ] && echo "$FILE_PATH" | grep -q "vault/"; then
    touch "${VAULT_DIR}/.index-stale" 2>/dev/null || true

    # --- Activity feed logging for vault events ---
    REPO_ROOT=$(git -C "$CWD" rev-parse --show-toplevel 2>/dev/null || echo "$CWD")
    LOGGER="${REPO_ROOT}/.sentinel/activity-logger.sh"
    # Source the activity logger from the plugin if available
    PLUGIN_LOGGER=""
    for candidate in \
        "$(dirname "$(dirname "$(readlink -f "$0" 2>/dev/null || echo "$0")")")/engine/activity-logger.sh" \
        "$(dirname "$0")/activity-logger.sh"; do
        if [ -f "$candidate" ]; then
            PLUGIN_LOGGER="$candidate"
            break
        fi
    done

    if [ -n "$PLUGIN_LOGGER" ]; then
        REPO_ROOT="$REPO_ROOT" source "$PLUGIN_LOGGER"

        REL_PATH="${FILE_PATH#${REPO_ROOT}/}"

        if echo "$FILE_PATH" | grep -q "vault/gotchas/"; then
            SLUG=$(basename "$FILE_PATH" .md)
            log_activity "Discovered gotcha: \`${SLUG}\` (${REL_PATH})"
        elif echo "$FILE_PATH" | grep -q "vault/investigations/"; then
            SLUG=$(basename "$FILE_PATH" .md)
            # Check if it's being resolved
            if grep -qi "status:.*resolved" "$FILE_PATH" 2>/dev/null; then
                log_activity "Resolved investigation: \`${SLUG}\`"
            else
                log_activity "Updated investigation: \`${SLUG}\` (${REL_PATH})"
            fi
        elif echo "$FILE_PATH" | grep -q "vault/decisions/"; then
            SLUG=$(basename "$FILE_PATH" .md)
            log_activity "Added decision: \`${SLUG}\` (${REL_PATH})"
        fi
    fi
fi

exit 0

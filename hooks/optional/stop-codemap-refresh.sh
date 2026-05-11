#!/bin/bash
# STOP HOOK (optional): Refresh codemap entries for files Claude edited.
#
# At session end, intersect the session's modified-files.txt with every
# codemap manifest under vault/. For manifests where Claude touched at least
# one tracked source file, spawn the refresh worker in the background so the
# Stop event returns immediately.
#
# This is the "Claude Code made local changes" branch of the codemap update
# story. Manual edits and `git pull` updates are handled by
# session-start-codemap-check.sh.
#
# Opt-in via .sentinel/config.json hooks.codemap_refresh: true.

set -euo pipefail

INPUT=$(cat)
CWD=$(echo "$INPUT" | jq -r '.cwd // empty')
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty')
STOP_HOOK_ACTIVE=$(echo "$INPUT" | jq -r '.stop_hook_active // false')

if [ "$STOP_HOOK_ACTIVE" = "true" ]; then
    exit 0
fi

VAULT_DIR="${CWD}/vault"
if [ ! -d "$VAULT_DIR" ]; then
    exit 0
fi

CONFIG_FILE="${CWD}/.sentinel/config.json"
CODEMAP_REFRESH=false
if [ -f "$CONFIG_FILE" ]; then
    CODEMAP_REFRESH=$(jq -r '.hooks.codemap_refresh // false' "$CONFIG_FILE" 2>/dev/null || echo "false")
fi
if [ "$CODEMAP_REFRESH" != "true" ]; then
    exit 0
fi

if [ -z "${ANTHROPIC_API_KEY:-}" ] || ! command -v python3 >/dev/null 2>&1; then
    exit 0
fi

# Locate the modified-files list for this session.
SENTINEL_DIR="${CWD}/.sentinel"
if [ -n "$SESSION_ID" ]; then
    SHORT_ID="${SESSION_ID:0:12}"
    SENTINEL_DIR="${CWD}/.sentinel/sessions/${SHORT_ID}"
fi
MODIFIED_FILE="${SENTINEL_DIR}/modified-files.txt"

if [ ! -f "$MODIFIED_FILE" ]; then
    exit 0
fi

FILE_COUNT=$(wc -l < "$MODIFIED_FILE" | tr -d ' ')
if [ "${FILE_COUNT:-0}" -lt 1 ]; then
    exit 0
fi

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"
HELPERS="${PLUGIN_ROOT}/scripts/codemap-helpers.sh"
WORKER="${PLUGIN_ROOT}/scripts/refresh-codemap.py"

if [ ! -f "$HELPERS" ] || [ ! -f "$WORKER" ]; then
    exit 0
fi

MANIFESTS=$(bash "$HELPERS" list-manifests "$CWD" 2>/dev/null || echo "")
if [ -z "$MANIFESTS" ]; then
    exit 0
fi

LOG_DIR="${CWD}/.sentinel"
mkdir -p "$LOG_DIR"
LOG_FILE="${LOG_DIR}/codemap-refresh.log"

while IFS= read -r manifest; do
    [ -z "$manifest" ] && continue
    DRIFT=$(CODEMAP_PROJECT_ROOT="$CWD" bash "$HELPERS" detect-drift-files "$manifest" "$MODIFIED_FILE" 2>/dev/null || echo "{}")
    NEEDS=$(echo "$DRIFT" | jq -r '((.modified // []) + (.deleted // [])) | length' 2>/dev/null || echo "0")
    if [ "${NEEDS:-0}" -gt 0 ]; then
        nohup python3 "$WORKER" \
            --manifest "$manifest" \
            --project-root "$CWD" \
            --paths-file "$MODIFIED_FILE" \
            >> "$LOG_FILE" 2>&1 &
        disown 2>/dev/null || true
    fi
done <<< "$MANIFESTS"

exit 0

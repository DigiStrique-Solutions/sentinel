#!/bin/bash
# SESSION-START HOOK (optional): Detect codemap drift from out-of-band changes.
#
# At the start of every session, scan every codemap manifest under vault/ for
# drift. Drift sources we care about: manual edits made between sessions, files
# pulled in by `git pull`, files added/deleted on disk. (Stop-time edits made
# by Claude in the previous session are caught by stop-codemap-refresh.sh, but
# we still scan in case that hook was disabled or skipped.)
#
# If any manifest shows drift AND background extraction prereqs are met
# (ANTHROPIC_API_KEY + python3 + opt-in flag), spawn the refresh worker in the
# background so session startup is not blocked.
#
# Opt-in via .sentinel/config.json hooks.codemap_refresh: true.

set -euo pipefail

INPUT=$(cat)
CWD=$(echo "$INPUT" | jq -r '.cwd // empty')
SOURCE=$(echo "$INPUT" | jq -r '.source // empty')

# Only run on actual session starts, not on /resume or /clear (the manifest
# scan would just no-op anyway but it's wasted I/O).
if [ "$SOURCE" != "startup" ] && [ "$SOURCE" != "resume" ]; then
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

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"
HELPERS="${PLUGIN_ROOT}/scripts/codemap-helpers.sh"
WORKER="${PLUGIN_ROOT}/scripts/refresh-codemap.py"

if [ ! -f "$HELPERS" ] || [ ! -f "$WORKER" ]; then
    exit 0
fi

# Find every manifest under the vault.
MANIFESTS=$(bash "$HELPERS" list-manifests "$CWD" 2>/dev/null || echo "")
if [ -z "$MANIFESTS" ]; then
    exit 0
fi

LOG_DIR="${CWD}/.sentinel"
mkdir -p "$LOG_DIR"
LOG_FILE="${LOG_DIR}/codemap-refresh.log"

DRIFT_COUNT=0
while IFS= read -r manifest; do
    [ -z "$manifest" ] && continue
    # Cheap drift detection — no API calls yet
    DRIFT=$(CODEMAP_PROJECT_ROOT="$CWD" bash "$HELPERS" detect-drift "$manifest" 2>/dev/null || echo "{}")
    NEEDS=$(echo "$DRIFT" | jq -r '((.modified // []) + (.added // []) + (.deleted // [])) | length' 2>/dev/null || echo "0")
    if [ "${NEEDS:-0}" -gt 0 ]; then
        DRIFT_COUNT=$((DRIFT_COUNT + NEEDS))
        # Spawn refresh worker in background, detached
        nohup python3 "$WORKER" \
            --manifest "$manifest" \
            --project-root "$CWD" \
            >> "$LOG_FILE" 2>&1 &
        disown 2>/dev/null || true
    fi
done <<< "$MANIFESTS"

# Output is delivered to Claude as additional context per the SessionStart
# hook spec (stdout from SessionStart hooks IS added to the agent's context).
if [ "$DRIFT_COUNT" -gt 0 ]; then
    echo "Sentinel: ${DRIFT_COUNT} codemap entries are being refreshed in the background (drift detected since last session)."
fi

exit 0

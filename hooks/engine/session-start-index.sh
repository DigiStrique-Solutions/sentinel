#!/bin/bash
# SESSION START HOOK: Rebuild vault index if stale
#
# Checks for a .index-stale marker file or missing index. If either condition
# is true, runs the index builder script in the background with a 3-second
# timeout so it doesn't block session start.
#
# The index enables fast keyword-based vault lookups in other hooks
# (pre-tool-gotcha, prompt-vault-search) instead of brute-force grep.

set -euo pipefail

INPUT=$(cat)
CWD=$(echo "$INPUT" | jq -r '.cwd // empty')

VAULT_DIR="${CWD}/vault"
INDEX_FILE="${VAULT_DIR}/.index.json"
STALE_MARKER="${VAULT_DIR}/.index-stale"
INDEX_SCRIPT="${CWD}/scripts/build-index.sh"

# Graceful exit if vault doesn't exist
if [ ! -d "$VAULT_DIR" ]; then
    exit 0
fi

# Also clear previous session's tracker on new session start
SENTINEL_DIR="${CWD}/.sentinel"
rm -rf "$SENTINEL_DIR" 2>/dev/null || true

# Check if index needs rebuilding:
# 1. Stale marker exists (set by post-tool-tracker when vault files change)
# 2. Index file doesn't exist at all
if [ ! -f "$STALE_MARKER" ] && [ -f "$INDEX_FILE" ]; then
    # Index exists and is not stale — nothing to do
    exit 0
fi

# Guard: index builder script must exist and be executable
if [ ! -x "$INDEX_SCRIPT" ]; then
    # Try alternate location inside vault
    INDEX_SCRIPT="${VAULT_DIR}/scripts/build-index.sh"
    if [ ! -x "$INDEX_SCRIPT" ]; then
        exit 0
    fi
fi

# Run index build in background with a 3-second timeout
# This prevents blocking session start if the vault is large
(
    # Use timeout command if available, otherwise use a subshell with kill
    if command -v timeout &>/dev/null; then
        timeout 3 bash "$INDEX_SCRIPT" "$VAULT_DIR" > /dev/null 2>&1
    else
        bash "$INDEX_SCRIPT" "$VAULT_DIR" > /dev/null 2>&1 &
        BUILD_PID=$!
        ( sleep 3; kill "$BUILD_PID" 2>/dev/null ) &
        WATCHDOG=$!
        wait "$BUILD_PID" 2>/dev/null || true
        kill "$WATCHDOG" 2>/dev/null || true
        wait "$WATCHDOG" 2>/dev/null || true
    fi

    # Remove stale marker on success
    rm -f "$STALE_MARKER" 2>/dev/null || true
) &

# Don't wait for the background process — let session start proceed
exit 0

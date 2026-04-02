#!/bin/bash
# STOP HOOK: Enforce vault maintenance before session ends
#
# At session end, checks whether the agent completed housekeeping tasks:
# 1. Changelog entry for today (if files were modified)
# 2. Investigation file (if failures were detected in transcript)
# 3. Open investigations reminder
# 4. Test file reminder (adversarial evaluation)
#
# Outputs warnings as a checklist. Does NOT block (exit 0) in v0.1 —
# just warns. This can be upgraded to exit 2 for blocking enforcement.
#
# Also cleans up .sentinel/ tracking directory and old session recovery files.

set -euo pipefail

INPUT=$(cat)
CWD=$(echo "$INPUT" | jq -r '.cwd // empty')
STOP_HOOK_ACTIVE=$(echo "$INPUT" | jq -r '.stop_hook_active // false')
TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.transcript_path // empty')

VAULT_DIR="${CWD}/vault"

# Graceful exit if vault doesn't exist
if [ ! -d "$VAULT_DIR" ]; then
    # Clean up sentinel tracker even without vault
    rm -rf "${CWD}/.sentinel" 2>/dev/null || true
    exit 0
fi

# Prevent infinite loop — if stop hook already fired once, let it through
if [ "$STOP_HOOK_ACTIVE" = "true" ]; then
    # Final cleanup on re-entry
    rm -rf "${CWD}/.sentinel" 2>/dev/null || true
    exit 0
fi

TODAY=$(date +%Y-%m-%d)
WARNINGS=""

# --- 1. Check if code files were modified this session ---
SENTINEL_DIR="${CWD}/.sentinel"
MODIFIED_FILE="${SENTINEL_DIR}/modified-files.txt"
FILES_CHANGED=""
FILE_COUNT=0

if [ -f "$MODIFIED_FILE" ]; then
    FILES_CHANGED=$(grep -E '\.(py|tsx?|jsx?|go|rs|rb|java|swift|kt|css|scss|sh)$' "$MODIFIED_FILE" | head -5 || echo "")
    FILE_COUNT=$(wc -l < "$MODIFIED_FILE" | tr -d ' ')
fi

# Trivial session escape hatch: 0-2 files modified skips changelog enforcement
SKIP_CHANGELOG=false
if [ "$FILE_COUNT" -le 2 ]; then
    SKIP_CHANGELOG=true
fi

if [ -n "$FILES_CHANGED" ] && [ "$SKIP_CHANGELOG" = "false" ]; then
    # Check for today's changelog entry
    if [ -d "${VAULT_DIR}/changelog" ]; then
        CHANGELOG_EXISTS=$(find "${VAULT_DIR}/changelog" -name "${TODAY}*" -type f 2>/dev/null | head -1)
        if [ -z "$CHANGELOG_EXISTS" ]; then
            WARNINGS="${WARNINGS}\n- [ ] NO CHANGELOG for today (${TODAY}). Files were modified — create a changelog entry."
        fi
    fi
fi

# --- 2. Check transcript for failure patterns ---
if [ -n "$TRANSCRIPT_PATH" ] && [ -f "$TRANSCRIPT_PATH" ]; then
    FAILURE_SIGNALS=$(tail -100 "$TRANSCRIPT_PATH" | grep -ciE "(failed|error|doesn.t work|broke|regression|rollback)" 2>/dev/null || echo "0")
    if [ "$FAILURE_SIGNALS" -gt 3 ]; then
        # Check if there's a recent investigation file
        RECENT_INVESTIGATION=$(find "${VAULT_DIR}/investigations" -name "20*" -mmin -60 -type f 2>/dev/null | head -1)
        if [ -z "$RECENT_INVESTIGATION" ]; then
            WARNINGS="${WARNINGS}\n- [ ] Multiple failure signals detected but NO investigation logged. Create vault/investigations/ entry."
        fi
    fi
fi

# --- 3. Remind about open investigations ---
if [ -d "${VAULT_DIR}/investigations" ]; then
    OPEN_COUNT=0
    for f in "${VAULT_DIR}/investigations"/*.md; do
        [ -f "$f" ] || continue
        [ "$(basename "$f")" = "_template.md" ] && continue
        if ! grep -qi "status:.*\(resolved\|implemented\|obsolete\)" "$f" 2>/dev/null; then
            OPEN_COUNT=$((OPEN_COUNT + 1))
        fi
    done
    if [ "$OPEN_COUNT" -gt 0 ]; then
        WARNINGS="${WARNINGS}\n- [ ] ${OPEN_COUNT} open investigation(s) in vault/investigations/ — update status if any were resolved this session."
    fi
fi

# --- 4. Check if test files were written — remind about adversarial eval ---
if [ -f "$MODIFIED_FILE" ]; then
    TEST_FILES=$(grep -cE '(test_|_test\.|\.test\.|\.spec\.)' "$MODIFIED_FILE" 2>/dev/null || echo "0")
    if [ "$TEST_FILES" -gt 0 ]; then
        WARNINGS="${WARNINGS}\n- [ ] ${TEST_FILES} test file(s) written — consider adversarial evaluation to verify test quality."
    fi
fi

# --- 5. Clean up old session recovery files ---
if [ -d "${VAULT_DIR}/session-recovery" ]; then
    # Compaction recovery files: delete after 4 hours
    find "${VAULT_DIR}/session-recovery" -name "20*-*.md" ! -name "summary-*" -mmin +240 -type f -delete 2>/dev/null || true
    # Session summaries: delete after 48 hours
    find "${VAULT_DIR}/session-recovery" -name "summary-*.md" -mmin +2880 -type f -delete 2>/dev/null || true
fi

# --- Output warnings ---
if [ -n "$WARNINGS" ]; then
    echo -e "VAULT MAINTENANCE CHECKLIST -- please address before stopping:\n${WARNINGS}"
fi

# Clean up sentinel tracking directory
rm -rf "${CWD}/.sentinel" 2>/dev/null || true

# v0.1: warn only, don't block
exit 0

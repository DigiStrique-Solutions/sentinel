#!/bin/bash
# SESSION START HOOK: Reload critical context after compaction
#
# Claude Code fires SessionStart with source="compact" after auto-compaction.
# By this point, conversation history is summarized and project instructions
# may be lost. This hook re-injects the most critical vault context so Claude
# doesn't start violating rules it was following perfectly before compaction.
#
# This is different from the general session-start-loader:
# - Loader runs on every session start (including fresh sessions)
# - This hook runs ONLY after compaction and is more aggressive about
#   reloading context — it prioritizes current task recovery over
#   general vault knowledge
#
# Triggers: SessionStart with source="compact"

set -euo pipefail

INPUT=$(cat)
CWD=$(echo "$INPUT" | jq -r '.cwd // empty')
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty')
SOURCE=$(echo "$INPUT" | jq -r '.source // empty')

[ -z "$CWD" ] && exit 0

# Only run after compaction — not on fresh session start
if [ "$SOURCE" != "compact" ]; then
    exit 0
fi

VAULT_DIR="${CWD}/vault"
if [ ! -d "$VAULT_DIR" ]; then
    exit 0
fi

OUTPUT=""

# --- 1. Reload the most recent session recovery file ---
# This was saved by pre-compact-save.sh moments ago
RECOVERY_FILE=""
if [ -d "${VAULT_DIR}/session-recovery" ]; then
    RECOVERY_FILE=$(find "${VAULT_DIR}/session-recovery" -name "*.md" -mmin -10 -type f 2>/dev/null | sort -r | head -1)
fi

if [ -n "$RECOVERY_FILE" ] && [ -f "$RECOVERY_FILE" ]; then
    RECOVERY_CONTENT=$(cat "$RECOVERY_FILE" | head -60)
    OUTPUT="${OUTPUT}\n## POST-COMPACTION CONTEXT RECOVERY\n\nContext was just compacted. Critical state reloaded from ${RECOVERY_FILE}:\n\n${RECOVERY_CONTENT}"
fi

# --- 2. Reload active todos (task completion state) ---
SENTINEL_DIR="${CWD}/.sentinel"
if [ -n "$SESSION_ID" ]; then
    SHORT_ID="${SESSION_ID:0:12}"
    TODO_FILE="${SENTINEL_DIR}/sessions/${SHORT_ID}/todos.json"
    if [ -f "$TODO_FILE" ]; then
        TODO_LIST=$(jq -r '.todos[] | "- [\(.status)] \(.content)"' "$TODO_FILE" 2>/dev/null || echo "")
        if [ -n "$TODO_LIST" ]; then
            OUTPUT="${OUTPUT}\n\n## ACTIVE TASK LIST (from before compaction)\n${TODO_LIST}\n\nResume from the first incomplete task."
        fi
    fi
fi

# --- 3. Reload open investigations (highest priority vault content) ---
if [ -d "${VAULT_DIR}/investigations" ]; then
    OPEN_INVESTIGATIONS=""
    for f in "${VAULT_DIR}/investigations"/*.md; do
        [ -f "$f" ] || continue
        [ "$(basename "$f")" = "_template.md" ] && continue
        if ! grep -qi "status:.*\(resolved\|implemented\|obsolete\)" "$f" 2>/dev/null; then
            FILENAME=$(basename "$f")
            OPEN_INVESTIGATIONS="${OPEN_INVESTIGATIONS}\n- **${FILENAME}**"
        fi
    done
    if [ -n "$OPEN_INVESTIGATIONS" ]; then
        OUTPUT="${OUTPUT}\n\n## OPEN INVESTIGATIONS (still active)\n${OPEN_INVESTIGATIONS}\nCheck these before attempting fixes — they document approaches that already failed."
    fi
fi

# --- 4. Reload bugfix mode flag ---
if [ -n "$SESSION_ID" ]; then
    BUGFIX_FLAG="${SENTINEL_DIR}/sessions/${SHORT_ID}/mode-bugfix"
    if [ -f "$BUGFIX_FLAG" ]; then
        OUTPUT="${OUTPUT}\n\n**BUG-FIX MODE ACTIVE** — This session is working on a bug fix. Reproduce the bug with a failing test before fixing."
    fi
fi

# --- Output ---
if [ -n "$OUTPUT" ]; then
    echo -e "COMPACTION DETECTED — Reloading critical context:\n${OUTPUT}\n\nIMPORTANT: Re-read CLAUDE.md for project rules. Compaction may have lost instructions you were following."
fi

exit 0

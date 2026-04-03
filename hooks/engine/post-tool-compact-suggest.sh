#!/bin/bash
# POST-TOOL HOOK (Bash): Suggest manual /compact before auto-compact triggers
#
# Tracks tool call count per session. After a configurable threshold (default: 80),
# suggests manual /compact at a logical boundary. This gives the user control
# over WHEN compaction happens — at a task boundary rather than mid-work.
#
# Auto-compact triggers at ~83% context capacity and destroys working memory.
# Manual /compact at 60-70% preserves more detail and lets the user add a
# focus message: /compact "Focus on implementing auth middleware next"
#
# Only suggests once — sets a flag after the first suggestion to avoid nagging.

set -euo pipefail

INPUT=$(cat)
CWD=$(echo "$INPUT" | jq -r '.cwd // empty')
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty')

[ -z "$CWD" ] && exit 0
[ -z "$SESSION_ID" ] && exit 0

# Setup tracking directory
SENTINEL_DIR="${CWD}/.sentinel"
SHORT_ID="${SESSION_ID:0:12}"
SENTINEL_DIR="${CWD}/.sentinel/sessions/${SHORT_ID}"
mkdir -p "$SENTINEL_DIR" 2>/dev/null || true

COUNTER_FILE="${SENTINEL_DIR}/tool-call-count"
SUGGESTED_FILE="${SENTINEL_DIR}/compact-suggested"

# Already suggested this session — don't nag
if [ -f "$SUGGESTED_FILE" ]; then
    exit 0
fi

# Increment counter
COUNT=0
if [ -f "$COUNTER_FILE" ]; then
    COUNT=$(cat "$COUNTER_FILE" 2>/dev/null || echo "0")
fi
COUNT=$((COUNT + 1))
echo "$COUNT" > "$COUNTER_FILE"

# Check threshold (configurable via .sentinel/config.json)
THRESHOLD=80
CONFIG_FILE="${CWD}/.sentinel/config.json"
if [ -f "$CONFIG_FILE" ]; then
    CUSTOM=$(jq -r '.compact_suggest_threshold // empty' "$CONFIG_FILE" 2>/dev/null || echo "")
    if [ -n "$CUSTOM" ] && [ "$CUSTOM" -gt 0 ] 2>/dev/null; then
        THRESHOLD="$CUSTOM"
    fi
fi

# Suggest at threshold
if [ "$COUNT" -eq "$THRESHOLD" ]; then
    touch "$SUGGESTED_FILE"
    echo "CONTEXT PRESSURE: ${COUNT} tool calls this session. Consider running /compact at a logical boundary to preserve context quality. Auto-compact at ~83% capacity loses more detail than manual compaction at 60-70%."
fi

exit 0

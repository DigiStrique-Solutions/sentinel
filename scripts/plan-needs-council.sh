#!/bin/bash
# plan-needs-council.sh — determine whether a plan should be reviewed by sentinel-plan-council
# before execution.
#
# Reads a plan markdown file and applies the trigger heuristic:
#   1. Explicit flag in header: `Council required: true` → council needed
#   2. Auto-trigger: file map has > N files (default 5) → council needed
#   3. Override: `Council required: false` always wins
#
# Future: also check vault/investigations/ for prior failures on this topic.
#
# Usage:
#   bash plan-needs-council.sh <plan_path> [file_threshold]
#
# Exit codes:
#   0 — council needed
#   1 — council not needed
#   2 — error (file missing, malformed)
#
# Stdout: JSON {"needed": true|false, "reasons": [...], "file_count": N, "explicit_flag": "true|false|absent"}

set -euo pipefail

PLAN_PATH="${1:-}"
FILE_THRESHOLD="${2:-5}"

if [ -z "$PLAN_PATH" ]; then
    echo "ERROR: plan_path required" >&2
    exit 2
fi

if [ ! -f "$PLAN_PATH" ]; then
    echo "ERROR: plan not found at $PLAN_PATH" >&2
    exit 2
fi

# --- Parse `Council required: ...` header line ---
# Looks for a line like: **Council required:** true
#                   or:  Council required: true
# Case-insensitive on the value.
EXPLICIT_FLAG=$(grep -iE '\*\*Council required:?\*\*|^Council required:' "$PLAN_PATH" 2>/dev/null \
    | head -1 \
    | sed -E 's/.*[Cc]ouncil [Rr]equired:?\*?\*? *//' \
    | sed -E 's/[^a-zA-Z].*//' \
    | tr '[:upper:]' '[:lower:]' \
    || echo "")

case "$EXPLICIT_FLAG" in
    true|yes|y) EXPLICIT_FLAG="true" ;;
    false|no|n) EXPLICIT_FLAG="false" ;;
    *)          EXPLICIT_FLAG="absent" ;;
esac

# --- Count files in the file map section ---
# A file map row looks like one of:
#   | `path/to/file.py` | New | ... |
#   - Create: `path/to/file.py`
#   - Modify: `path/to/file.py`
# Count distinct backticked paths in lines that look like file map entries.
FILE_COUNT=0
if [ -s "$PLAN_PATH" ]; then
    FILE_COUNT=$(grep -E '^\s*[-|*]\s' "$PLAN_PATH" \
        | grep -oE '`[^`]+\.(py|ts|tsx|js|jsx|go|rs|rb|java|kt|swift|cpp|c|h|hpp|sh|md|yml|yaml|json|toml|sql)`' \
        | sort -u \
        | wc -l \
        | tr -d ' ')
fi

# --- Apply heuristic ---
NEEDED=false
REASONS=()

case "$EXPLICIT_FLAG" in
    true)
        NEEDED=true
        REASONS+=("explicit_flag")
        ;;
    false)
        # Explicit override wins — even if file count is high, user asked to skip
        NEEDED=false
        REASONS+=("explicit_override_skip")
        ;;
    absent)
        # Apply auto-trigger
        if [ "$FILE_COUNT" -gt "$FILE_THRESHOLD" ]; then
            NEEDED=true
            REASONS+=("file_count_above_threshold")
        else
            REASONS+=("file_count_below_threshold")
        fi
        ;;
esac

# --- Output JSON summary ---
REASONS_JSON=$(printf '%s\n' "${REASONS[@]}" | jq -R . | jq -s .)

jq -n \
    --argjson needed "$NEEDED" \
    --argjson reasons "$REASONS_JSON" \
    --argjson file_count "$FILE_COUNT" \
    --argjson threshold "$FILE_THRESHOLD" \
    --arg explicit_flag "$EXPLICIT_FLAG" \
    --arg plan_path "$PLAN_PATH" \
    '{
        plan_path: $plan_path,
        needed: $needed,
        reasons: $reasons,
        file_count: $file_count,
        threshold: $threshold,
        explicit_flag: $explicit_flag
    }'

# Exit code matches the boolean
if [ "$NEEDED" = "true" ]; then
    exit 0
else
    exit 1
fi

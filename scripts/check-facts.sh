#!/bin/bash
# CLAUDE.MD FACT CHECKER: Verify numerical claims against the actual codebase
#
# Reads user-defined fact-check rules from .sentinel/fact-checks.yml and verifies
# each claim in CLAUDE.md against a grep/find count in the codebase.
#
# If no .sentinel/fact-checks.yml exists, the script exits silently — there's
# nothing project-specific to check.
#
# Config format (.sentinel/fact-checks.yml):
#
#   checks:
#     - description: "API endpoints"
#       pattern: '[0-9]+ API endpoints'
#       command: "grep -r '@app\.\(get\|post\|put\|delete\)' src/ | wc -l"
#     - description: "ORM models"
#       pattern: '[0-9]+ ORM models'
#       command: "find src/models/ -name '*.py' ! -name '__init__.py' -type f | wc -l"
#
# Only checks hard numbers — does not validate prose or descriptions.
# Outputs warnings when a claimed number differs from reality by >10%.
#
# Usage: ./check-facts.sh <project-root>

set -euo pipefail

PROJECT_ROOT="${1:-.}"
CLAUDE_MD="${PROJECT_ROOT}/CLAUDE.md"
CONFIG="${PROJECT_ROOT}/.sentinel/fact-checks.yml"

# Exit silently if no CLAUDE.md
if [ ! -f "$CLAUDE_MD" ]; then
    exit 0
fi

# Exit silently if no fact-check config — nothing to check
if [ ! -f "$CONFIG" ]; then
    exit 0
fi

WARNINGS=""

# Helper: warn if claimed count differs from actual by >10%
check_count() {
    local description="$1"
    local claimed="$2"
    local actual="$3"

    if [ "$claimed" -eq 0 ] || [ "$actual" -eq 0 ]; then
        return
    fi

    local diff=$(( actual - claimed ))
    if [ "$diff" -lt 0 ]; then
        diff=$(( -diff ))
    fi

    # Calculate 10% threshold
    local threshold=$(( claimed / 10 ))
    if [ "$threshold" -lt 1 ]; then
        threshold=1
    fi

    if [ "$diff" -gt "$threshold" ]; then
        WARNINGS="${WARNINGS}\n  - ${description}: CLAUDE.md says ${claimed}, actual is ${actual}"
    fi
}

# --- Parse config and run checks ---
# Simple line-by-line YAML parser (no external deps)
CURRENT_DESC=""
CURRENT_PATTERN=""
CURRENT_COMMAND=""

process_check() {
    if [ -n "$CURRENT_DESC" ] && [ -n "$CURRENT_PATTERN" ] && [ -n "$CURRENT_COMMAND" ]; then
        # Extract claimed number from CLAUDE.md using the pattern
        CLAIMED=$(grep -oE "$CURRENT_PATTERN" "$CLAUDE_MD" 2>/dev/null | head -1 | grep -oE '^[0-9]+' || echo "0")
        if [ "$CLAIMED" -gt 0 ]; then
            # Run the count command from the project root
            ACTUAL=$(cd "$PROJECT_ROOT" && eval "$CURRENT_COMMAND" 2>/dev/null | tr -d ' ' || echo "0")
            if [ "$ACTUAL" -gt 0 ]; then
                check_count "$CURRENT_DESC" "$CLAIMED" "$ACTUAL"
            fi
        fi
    fi
}

while IFS= read -r line || [ -n "$line" ]; do
    # Skip comments and empty lines
    [[ "$line" =~ ^[[:space:]]*# ]] && continue
    [[ "$line" =~ ^[[:space:]]*$ ]] && continue

    # Detect new check item
    if [[ "$line" =~ ^[[:space:]]*-[[:space:]]*description: ]]; then
        # Process previous check if exists
        process_check
        CURRENT_DESC=$(echo "$line" | sed 's/.*description:[[:space:]]*//' | sed 's/^"//' | sed 's/"$//')
        CURRENT_PATTERN=""
        CURRENT_COMMAND=""
    elif [[ "$line" =~ ^[[:space:]]*pattern: ]]; then
        CURRENT_PATTERN=$(echo "$line" | sed 's/.*pattern:[[:space:]]*//' | sed 's/^"//' | sed "s/^'//" | sed 's/"$//' | sed "s/'$//")
    elif [[ "$line" =~ ^[[:space:]]*command: ]]; then
        CURRENT_COMMAND=$(echo "$line" | sed 's/.*command:[[:space:]]*//' | sed 's/^"//' | sed "s/^'//" | sed 's/"$//' | sed "s/'$//")
    fi
done < "$CONFIG"

# Process the last check
process_check

# --- Output ---
if [ -n "$WARNINGS" ]; then
    echo -e "CLAUDE.md FACT CHECK — numbers may be outdated:${WARNINGS}"
    echo "  Update CLAUDE.md with current counts, or the numbers will mislead every session."
fi

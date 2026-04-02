#!/bin/bash
# CLAUDE.MD FACT CHECKER: Verify numerical claims against the actual codebase
#
# Scans CLAUDE.md for patterns like "209 connector tools", "20 controllers",
# and verifies them against the actual file/symbol counts.
#
# Only checks hard numbers — does not validate prose or descriptions.
# Outputs warnings when a claimed number differs from reality by >10%.
#
# Usage: ./check-facts.sh <project-root>

set -euo pipefail

PROJECT_ROOT="${1:-.}"
CLAUDE_MD="${PROJECT_ROOT}/CLAUDE.md"

# Exit silently if no CLAUDE.md
if [ ! -f "$CLAUDE_MD" ]; then
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

# --- Check connector tool counts ---
# Look for patterns like "209 connector tools" or "82 Google Ads"
CLAIMED_TOTAL=$(grep -oE '[0-9]+ (connector )?tools' "$CLAUDE_MD" 2>/dev/null | head -1 | grep -oE '^[0-9]+' || echo "0")
if [ "$CLAIMED_TOTAL" -gt 0 ]; then
    # Count @connector_tool decorators
    ACTUAL_TOTAL=$(grep -r "@connector_tool" "${PROJECT_ROOT}/strique-ai-server/src/connectors/" 2>/dev/null | wc -l | tr -d ' ' || echo "0")
    if [ "$ACTUAL_TOTAL" -gt 0 ]; then
        check_count "Connector tools" "$CLAIMED_TOTAL" "$ACTUAL_TOTAL"
    fi
fi

# --- Check per-platform tool counts ---
for platform_info in "Google Ads:google_ads" "LinkedIn:linkedin" "Meta:meta"; do
    PLATFORM_NAME="${platform_info%%:*}"
    PLATFORM_DIR="${platform_info##*:}"

    CLAIMED=$(grep -oE "[0-9]+ ${PLATFORM_NAME}" "$CLAUDE_MD" 2>/dev/null | head -1 | grep -oE '^[0-9]+' || echo "0")
    if [ "$CLAIMED" -gt 0 ]; then
        ACTUAL=$(grep -r "@connector_tool" "${PROJECT_ROOT}/strique-ai-server/src/connectors/${PLATFORM_DIR}/" 2>/dev/null | wc -l | tr -d ' ' || echo "0")
        if [ "$ACTUAL" -gt 0 ]; then
            check_count "${PLATFORM_NAME} tools" "$CLAIMED" "$ACTUAL"
        fi
    fi
done

# --- Check controller counts ---
CLAIMED_CONTROLLERS=$(grep -oE '[0-9]+ controllers' "$CLAUDE_MD" 2>/dev/null | head -1 | grep -oE '^[0-9]+' || echo "0")
if [ "$CLAIMED_CONTROLLERS" -gt 0 ]; then
    ACTUAL_CONTROLLERS=$(find "${PROJECT_ROOT}/strique-ai-server/src/controllers/" -name "*.py" ! -name "__init__.py" ! -name "*.pyc" -type f 2>/dev/null | wc -l | tr -d ' ' || echo "0")
    if [ "$ACTUAL_CONTROLLERS" -gt 0 ]; then
        check_count "Controllers" "$CLAIMED_CONTROLLERS" "$ACTUAL_CONTROLLERS"
    fi
fi

# --- Check ORM entity counts ---
CLAIMED_ENTITIES=$(grep -oE '[0-9]+ ORM entit' "$CLAUDE_MD" 2>/dev/null | head -1 | grep -oE '^[0-9]+' || echo "0")
if [ "$CLAIMED_ENTITIES" -gt 0 ]; then
    ACTUAL_ENTITIES=$(find "${PROJECT_ROOT}/strique-ai-server/src/entities/" -name "*.py" ! -name "__init__.py" ! -name "*.pyc" -type f 2>/dev/null | wc -l | tr -d ' ' || echo "0")
    if [ "$ACTUAL_ENTITIES" -gt 0 ]; then
        check_count "ORM entities" "$CLAIMED_ENTITIES" "$ACTUAL_ENTITIES"
    fi
fi

# --- Check SKILL.md file counts ---
CLAIMED_SKILLS=$(grep -oE '[0-9]+ SKILL\.md' "$CLAUDE_MD" 2>/dev/null | head -1 | grep -oE '^[0-9]+' || echo "0")
if [ "$CLAIMED_SKILLS" -gt 0 ]; then
    ACTUAL_SKILLS=$(find "${PROJECT_ROOT}/strique-ai-server/src/" -name "SKILL.md" -type f 2>/dev/null | wc -l | tr -d ' ' || echo "0")
    if [ "$ACTUAL_SKILLS" -gt 0 ]; then
        check_count "SKILL.md files" "$CLAIMED_SKILLS" "$ACTUAL_SKILLS"
    fi
fi

# --- Check API client module counts ---
CLAIMED_API=$(grep -oE '[0-9]+ API client' "$CLAUDE_MD" 2>/dev/null | head -1 | grep -oE '^[0-9]+' || echo "0")
if [ "$CLAIMED_API" -gt 0 ]; then
    ACTUAL_API=$(find "${PROJECT_ROOT}/strique-web-app/src/lib/API/" -name "*.ts" ! -name "*.spec.*" ! -name "*.test.*" -type f 2>/dev/null | wc -l | tr -d ' ' || echo "0")
    if [ "$ACTUAL_API" -gt 0 ]; then
        check_count "API client modules" "$CLAIMED_API" "$ACTUAL_API"
    fi
fi

# --- Output ---
if [ -n "$WARNINGS" ]; then
    echo -e "CLAUDE.md FACT CHECK — numbers may be outdated:${WARNINGS}"
    echo "  Update CLAUDE.md with current counts, or the numbers will mislead every session."
fi

#!/bin/bash
# UPDATE PATTERN CONFIDENCE: Scans vault/patterns/learned/ and updates confidence scores.
# Patterns used >5 times get promoted. Patterns unused for 30+ days get flagged.
#
# Usage: update-confidence.sh <vault_dir>
#
# Actions:
#   - Scans all pattern files in vault/patterns/learned/
#   - Promotes patterns with references >= 5 (confidence capped at 1.0)
#   - Flags patterns not seen in 30+ days for review
#   - Reports summary of all pattern states

set -euo pipefail

VAULT_DIR="${1:?Usage: update-confidence.sh <vault_dir>}"
PATTERN_DIR="${VAULT_DIR}/patterns/learned"

if [ ! -d "$PATTERN_DIR" ]; then
    echo "No patterns directory found at ${PATTERN_DIR}"
    exit 0
fi

TOTAL=0
PROMOTED=0
FLAGGED=0
HEALTHY=0

TODAY_EPOCH=$(date +%s)
THIRTY_DAYS=$((30 * 24 * 60 * 60))

echo "=== Pattern Confidence Report ==="
echo ""

# Use process substitution (not pipe) to avoid subshell variable loss
while read -r filepath; do
    filename=$(basename "$filepath" .md)
    TOTAL=$((TOTAL + 1))

    # Read frontmatter values
    confidence=$(grep "^confidence:" "$filepath" | head -1 | awk '{print $2}')
    references=$(grep "^references:" "$filepath" | head -1 | awk '{print $2}')
    observed=$(grep "^observed:" "$filepath" | head -1 | awk '{print $2}')
    last_seen=$(grep "^last_seen:" "$filepath" | head -1 | awk '{print $2}')

    confidence="${confidence:-0.5}"
    references="${references:-0}"
    observed="${observed:-1}"
    last_seen="${last_seen:-}"

    # Check if pattern should be promoted (references >= 5)
    if [ "$references" -ge 5 ]; then
        # Use awk for float comparison (bc may not be available)
        if awk "BEGIN {exit ($confidence >= 0.9) ? 1 : 0}"; then
            NEW_CONF="0.9"
            PROMOTED=$((PROMOTED + 1))
            echo "PROMOTED: ${filename} (${references} references, confidence ${confidence} -> ${NEW_CONF})"

            # Update confidence in file
            if [[ "$OSTYPE" == "darwin"* ]]; then
                sed -i '' "s/^confidence: .*/confidence: ${NEW_CONF}/" "$filepath"
            else
                sed -i "s/^confidence: .*/confidence: ${NEW_CONF}/" "$filepath"
            fi
        else
            HEALTHY=$((HEALTHY + 1))
        fi
    fi

    # Check if pattern is stale (not seen in 30+ days)
    if [ -n "$last_seen" ]; then
        # Convert last_seen date to epoch
        if [[ "$OSTYPE" == "darwin"* ]]; then
            last_seen_epoch=$(date -j -f "%Y-%m-%d" "$last_seen" "+%s" 2>/dev/null || echo "0")
        else
            last_seen_epoch=$(date -d "$last_seen" "+%s" 2>/dev/null || echo "0")
        fi

        if [ "$last_seen_epoch" -gt 0 ]; then
            age=$((TODAY_EPOCH - last_seen_epoch))
            if [ "$age" -gt "$THIRTY_DAYS" ]; then
                days_ago=$((age / 86400))
                FLAGGED=$((FLAGGED + 1))
                echo "STALE: ${filename} (last seen ${days_ago} days ago, confidence ${confidence})"
            fi
        fi
    fi
done < <(find "$PATTERN_DIR" -name "*.md" -type f 2>/dev/null | sort)

echo ""
echo "=== Summary ==="
echo "Total patterns scanned: $(find "$PATTERN_DIR" -name "*.md" -type f 2>/dev/null | wc -l | tr -d ' ')"
echo "Promoted (>5 references): ${PROMOTED}"
echo "Flagged (>30 days stale): ${FLAGGED}"

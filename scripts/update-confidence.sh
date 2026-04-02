#!/bin/bash
# UPDATE PATTERN CONFIDENCE: Create, observe, or contradict learned patterns.
#
# Usage: update-confidence.sh <vault_dir> <action> <pattern-name> [area]
#   create      — new pattern at confidence 0.5
#   observe     — bump confidence +0.1 (cap at 1.0)
#   contradict  — drop confidence -0.1 (auto-delete below 0.3)
#
# Pattern files live in vault/patterns/learned/ with YAML frontmatter.
# If a pattern has references >= 3, it is considered well-established.
# If confidence < 0.3 after 5+ observations, the pattern is auto-deleted.

set -euo pipefail

VAULT_DIR="${1:?Usage: update-confidence.sh <vault_dir> <action> <pattern-name> [area]}"
ACTION="${2:?Missing action: create|observe|contradict}"
PATTERN_NAME="${3:?Missing pattern name}"
AREA="${4:-general}"

PATTERN_DIR="${VAULT_DIR}/patterns/learned"
PATTERN_FILE="${PATTERN_DIR}/${PATTERN_NAME}.md"

mkdir -p "$PATTERN_DIR"

case "$ACTION" in
    create)
        if [ -f "$PATTERN_FILE" ]; then
            echo "Pattern '${PATTERN_NAME}' already exists — treating as observe"
            ACTION="observe"
        else
            cat > "$PATTERN_FILE" << EOF
---
pattern: ${PATTERN_NAME}
area: ${AREA}
confidence: 0.5
observed: 1
references: 0
last_seen: $(date +%Y-%m-%d)
---

# Pattern: ${PATTERN_NAME}

(Description to be filled — explain what the pattern is, when it applies, and why it matters)

## When to Apply

(Describe the trigger conditions)

## Example

(Show a concrete example if applicable)
EOF
            echo "Created pattern: ${PATTERN_FILE}"
            exit 0
        fi
        ;;
    observe|contradict)
        if [ ! -f "$PATTERN_FILE" ]; then
            echo "Pattern '${PATTERN_NAME}' does not exist. Use 'create' first."
            exit 1
        fi
        ;;
    *)
        echo "Unknown action: ${ACTION}. Use create|observe|contradict."
        exit 1
        ;;
esac

# Read current values from frontmatter
CURRENT_CONF=$(grep "^confidence:" "$PATTERN_FILE" | head -1 | awk '{print $2}')
CURRENT_OBS=$(grep "^observed:" "$PATTERN_FILE" | head -1 | awk '{print $2}')
CURRENT_REFS=$(grep "^references:" "$PATTERN_FILE" | head -1 | awk '{print $2}')

# Defaults if missing
CURRENT_CONF="${CURRENT_CONF:-0.5}"
CURRENT_OBS="${CURRENT_OBS:-1}"
CURRENT_REFS="${CURRENT_REFS:-0}"

case "$ACTION" in
    observe)
        # Bump confidence by 0.1, cap at 1.0
        NEW_CONF=$(echo "$CURRENT_CONF + 0.1" | bc)
        if [ "$(echo "$NEW_CONF > 1.0" | bc)" -eq 1 ]; then
            NEW_CONF="1.0"
        fi
        NEW_OBS=$((CURRENT_OBS + 1))
        NEW_REFS=$((CURRENT_REFS + 1))

        # Check if pattern is now well-established
        if [ "$NEW_REFS" -ge 3 ]; then
            echo "Pattern '${PATTERN_NAME}' is well-established (${NEW_REFS} references)"
        fi

        echo "Observed pattern '${PATTERN_NAME}': confidence ${CURRENT_CONF} → ${NEW_CONF} (${NEW_OBS} observations, ${NEW_REFS} references)"
        ;;
    contradict)
        # Drop confidence by 0.1
        NEW_CONF=$(echo "$CURRENT_CONF - 0.1" | bc)
        NEW_OBS=$((CURRENT_OBS + 1))
        NEW_REFS="${CURRENT_REFS}"

        # Auto-delete if confidence below 0.3 AND enough observations to be sure
        if [ "$(echo "$NEW_CONF < 0.3" | bc)" -eq 1 ]; then
            if [ "$NEW_OBS" -ge 5 ]; then
                echo "Pattern '${PATTERN_NAME}' confidence dropped to ${NEW_CONF} after ${NEW_OBS} observations — deleting (below 0.3 threshold with 5+ observations)"
                rm "$PATTERN_FILE"
                exit 0
            else
                echo "Pattern '${PATTERN_NAME}' confidence at ${NEW_CONF} but only ${NEW_OBS} observations — keeping (need 5+ to auto-delete)"
            fi
        fi

        echo "Contradicted pattern '${PATTERN_NAME}': confidence ${CURRENT_CONF} → ${NEW_CONF}"
        ;;
esac

# Update frontmatter in place (macOS sed -i '' / Linux sed -i)
if [[ "$OSTYPE" == "darwin"* ]]; then
    sed -i '' "s/^confidence: .*/confidence: ${NEW_CONF}/" "$PATTERN_FILE"
    sed -i '' "s/^observed: .*/observed: ${NEW_OBS}/" "$PATTERN_FILE"
    sed -i '' "s/^references: .*/references: ${NEW_REFS}/" "$PATTERN_FILE"
    sed -i '' "s/^last_seen: .*/last_seen: $(date +%Y-%m-%d)/" "$PATTERN_FILE"
else
    sed -i "s/^confidence: .*/confidence: ${NEW_CONF}/" "$PATTERN_FILE"
    sed -i "s/^observed: .*/observed: ${NEW_OBS}/" "$PATTERN_FILE"
    sed -i "s/^references: .*/references: ${NEW_REFS}/" "$PATTERN_FILE"
    sed -i "s/^last_seen: .*/last_seen: $(date +%Y-%m-%d)/" "$PATTERN_FILE"
fi

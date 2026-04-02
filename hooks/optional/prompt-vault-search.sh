#!/bin/bash
# USER PROMPT SUBMIT HOOK (optional): Search vault for relevant context
#
# When the user submits a prompt, extracts keywords and searches the vault
# for matching investigations, gotchas, and decisions. Injects matches as
# additional context so the agent doesn't attempt approaches that already
# failed or miss known pitfalls.
#
# Uses vault/.index.json for fast tag/title lookup if available,
# falls back to grep-based content search otherwise.
# Capped at 5 matches to avoid context bloat.

set -euo pipefail

INPUT=$(cat)
PROMPT=$(echo "$INPUT" | jq -r '.prompt // empty')
CWD=$(echo "$INPUT" | jq -r '.cwd // empty')

VAULT_DIR="${CWD}/vault"

# Graceful exit if vault doesn't exist
if [ ! -d "$VAULT_DIR" ]; then
    exit 0
fi

# Skip very short prompts (greetings, confirmations)
if [ ${#PROMPT} -lt 20 ]; then
    exit 0
fi

# Extract keywords from the prompt (lowercase, remove common stop words)
KEYWORDS=$(echo "$PROMPT" | tr '[:upper:]' '[:lower:]' | tr -cs '[:alnum:]' '\n' | \
    grep -vE '^(the|a|an|is|are|was|were|be|been|being|have|has|had|do|does|did|will|would|could|should|may|might|can|shall|must|need|want|please|help|fix|add|make|get|set|use|try|look|check|find|show|give|take|let|run|put|i|my|me|we|our|you|your|it|its|this|that|these|those|and|or|but|if|then|else|when|how|what|why|where|which|who|not|no|so|to|of|in|on|at|by|for|with|from|into|about|up|out|over)$' | \
    sort -u | head -10)

if [ -z "$KEYWORDS" ]; then
    exit 0
fi

MATCHES=""
MATCH_COUNT=0
INDEX_FILE="${VAULT_DIR}/.index.json"

# Fast path: use vault index if available
if [ -f "$INDEX_FILE" ]; then
    SEEN=""
    for kw in $KEYWORDS; do
        [ "$MATCH_COUNT" -ge 5 ] && break

        # Search tags index
        TAG_HITS=$(jq -r --arg kw "$kw" '.tags[$kw][]? // empty' "$INDEX_FILE" 2>/dev/null || echo "")

        # Search entry titles for keyword
        TITLE_HITS=$(jq -r --arg kw "$kw" '
            .entries | to_entries[] |
            select(.value.title | ascii_downcase | contains($kw)) |
            .key' "$INDEX_FILE" 2>/dev/null || echo "")

        for hit in $TAG_HITS $TITLE_HITS; do
            [ -z "$hit" ] && continue
            [ "$MATCH_COUNT" -ge 5 ] && break
            # Deduplicate
            if ! echo "$SEEN" | grep -q "$hit"; then
                SEEN="${SEEN} ${hit}"
                MATCHES="${MATCHES}\n- vault/${hit}"
                MATCH_COUNT=$((MATCH_COUNT + 1))
            fi
        done
    done
else
    # Fallback: brute-force grep search across vault directories
    for dir in investigations gotchas decisions; do
        [ "$MATCH_COUNT" -ge 5 ] && break
        [ -d "${VAULT_DIR}/${dir}" ] || continue

        for f in "${VAULT_DIR}/${dir}"/*.md; do
            [ -f "$f" ] || continue
            [ "$MATCH_COUNT" -ge 5 ] && break
            [ "$(basename "$f")" = "_template.md" ] && continue

            FILENAME=$(basename "$f")
            for kw in $KEYWORDS; do
                if grep -qil "$kw" "$f" 2>/dev/null; then
                    MATCHES="${MATCHES}\n- vault/${dir}/${FILENAME}"
                    MATCH_COUNT=$((MATCH_COUNT + 1))
                    break
                fi
            done
        done
    done
fi

# Output matched entries as additional context
if [ -n "$MATCHES" ]; then
    CONTEXT_MSG="VAULT MATCHES for this prompt -- READ before attempting work:${MATCHES}\n\nRead matched files FIRST to avoid repeating past failed approaches."
    echo -e "$CONTEXT_MSG"
fi

exit 0

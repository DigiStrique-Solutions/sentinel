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

# Resolve vault paths — search both repo and global vaults.
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"
# shellcheck source=/dev/null
source "${PLUGIN_ROOT}/scripts/resolve-vaults.sh"

REPO_VAULT=$(resolve_repo_vault "$CWD")
GLOBAL_VAULT=$(resolve_global_vault "$CWD")
VAULT_DIRS=$(resolve_all_vaults "$CWD")
VAULT_DIR="$REPO_VAULT"  # kept for index lookup fallback

# Check if this optional hook is enabled via config
CONFIG_FILE="${CWD}/.sentinel/config.json"
if [ -f "$CONFIG_FILE" ]; then
    ENABLED=$(jq -r '.hooks.vault_search_on_prompt // false' "$CONFIG_FILE" 2>/dev/null || echo "false")
else
    ENABLED="false"
fi
[ "$ENABLED" != "true" ] && exit 0

# Graceful exit if no vault exists at all
if [ -z "$VAULT_DIRS" ]; then
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
    # Fallback: brute-force grep search across both vaults
    while IFS= read -r VD; do
        [ -z "$VD" ] && continue
        [ "$MATCH_COUNT" -ge 5 ] && break

        LABEL=""
        if [ "$VD" = "$GLOBAL_VAULT" ]; then
            LABEL=" [global]"
        fi

        for dir in investigations gotchas decisions; do
            [ "$MATCH_COUNT" -ge 5 ] && break
            [ -d "${VD}/${dir}" ] || continue

            for f in "${VD}/${dir}"/*.md; do
                [ -f "$f" ] || continue
                [ "$MATCH_COUNT" -ge 5 ] && break
                [ "$(basename "$f")" = "_template.md" ] && continue

                FILENAME=$(basename "$f")
                for kw in $KEYWORDS; do
                    if grep -qil "$kw" "$f" 2>/dev/null; then
                        MATCHES="${MATCHES}\n- ${VD}/${dir}/${FILENAME}${LABEL}"
                        MATCH_COUNT=$((MATCH_COUNT + 1))
                        break
                    fi
                done
            done
        done
    done <<< "$VAULT_DIRS"
fi

# Output matched entries as additional context
if [ -n "$MATCHES" ]; then
    CONTEXT_MSG="VAULT MATCHES for this prompt -- READ before attempting work:${MATCHES}\n\nRead matched files FIRST to avoid repeating past failed approaches."
    echo -e "$CONTEXT_MSG"
fi

exit 0

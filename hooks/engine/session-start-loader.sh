#!/bin/bash
# SESSION START HOOK: Load vault context into every new session
#
# Injects critical vault knowledge at session start so the agent is aware of:
# - Open investigations (prevents repeating failed approaches)
# - Known gotchas (prevents known mistakes)
# - Recent session recovery files (enables cross-session continuity)
#
# Uses a TOKEN BUDGET to keep output lean. Priority order:
# 1. Open investigations (highest — prevents repeating failures)
# 2. Gotchas relevant to recent git changes
# 3. Session recovery (if recent)
# 4. Remaining gotchas by recency
# 5. Learned patterns
# 6. Team activity (lowest priority)
#
# Budget is ~10000 tokens by default (≈35000 chars). Sections are added
# in priority order and skipped when the budget is exhausted.

set -euo pipefail

INPUT=$(cat)
CWD=$(echo "$INPUT" | jq -r '.cwd // empty')

# Resolve vault directory relative to project root
VAULT_DIR="${CWD}/vault"

# Graceful exit if vault doesn't exist — project hasn't adopted vault yet
if [ ! -d "$VAULT_DIR" ]; then
    exit 0
fi

# --- Token budget management ---
# Default budget: ~10000 tokens ≈ 35000 chars (using 3.5 chars/token heuristic)
# This is <5% of Sonnet's 200K window and <1% of Opus's 1M window.
TOKEN_BUDGET="${SENTINEL_TOKEN_BUDGET:-10000}"
CHAR_BUDGET=$(( TOKEN_BUDGET * 35 / 10 ))
CHARS_USED=0

# Estimate chars of a string
estimate_chars() {
    echo -n "$1" | wc -c | tr -d ' '
}

# Check if adding content would exceed budget
budget_allows() {
    local new_chars
    new_chars=$(estimate_chars "$1")
    if [ $(( CHARS_USED + new_chars )) -le "$CHAR_BUDGET" ]; then
        return 0
    else
        return 1
    fi
}

# Add content to context if budget allows, return 0 if added, 1 if skipped
add_to_context() {
    local content="$1"
    local new_chars
    new_chars=$(estimate_chars "$content")
    if [ $(( CHARS_USED + new_chars )) -le "$CHAR_BUDGET" ]; then
        CONTEXT="${CONTEXT}${content}"
        CHARS_USED=$(( CHARS_USED + new_chars ))
        return 0
    fi
    return 1
}

# Build context string to inject into the session
CONTEXT=""

# --- Get recently changed directories for relevance filtering ---
CHANGED_DIRS=""
if command -v git &>/dev/null && git -C "$CWD" rev-parse --git-dir &>/dev/null 2>&1; then
    CHANGED_DIRS=$(git -C "$CWD" diff --name-only HEAD~5 2>/dev/null | sed 's|/[^/]*$||' | sort -u || echo "")
fi

# --- PRIORITY 1: Load open investigations (most critical) ---
# These prevent the agent from repeating approaches that already failed.
if [ -d "${VAULT_DIR}/investigations" ]; then
    OPEN_INVESTIGATIONS=""
    for f in "${VAULT_DIR}/investigations"/*.md; do
        [ -f "$f" ] || continue
        [ "$(basename "$f")" = "_template.md" ] && continue

        # Skip resolved/implemented/obsolete investigations
        if ! grep -qi "status:.*\(resolved\|implemented\|obsolete\)" "$f" 2>/dev/null; then
            FILENAME=$(basename "$f")
            # Extract first 3 lines after frontmatter for a brief summary
            SUMMARY=$(awk '/^---$/{n++; next} n==1{if(NR<=6) print}' "$f" | head -3)
            OPEN_INVESTIGATIONS="${OPEN_INVESTIGATIONS}\n- **${FILENAME}**: ${SUMMARY}"
        fi
    done

    if [ -n "$OPEN_INVESTIGATIONS" ]; then
        SECTION="\n\n## OPEN INVESTIGATIONS (check before attempting fixes)\n${OPEN_INVESTIGATIONS}"
        add_to_context "$SECTION" || true  # Always try — highest priority

        # Track loaded investigations for /sentinel-stats
        SENTINEL_STATS_DIR="${CWD}/.sentinel"
        mkdir -p "$SENTINEL_STATS_DIR" 2>/dev/null || true
        echo -e "$OPEN_INVESTIGATIONS" | grep -oE '\*\*[^*]+\*\*' | sed 's/\*\*//g' > "${SENTINEL_STATS_DIR}/investigations-loaded.txt" 2>/dev/null || true
    fi

    # Count resolved investigations without loading them
    RESOLVED_COUNT=0
    if [ -d "${VAULT_DIR}/investigations/resolved" ]; then
        RESOLVED_COUNT=$(find "${VAULT_DIR}/investigations/resolved" -name "*.md" -type f 2>/dev/null | wc -l | tr -d ' ')
    fi
    if [ "$RESOLVED_COUNT" -gt 0 ]; then
        add_to_context "\n\n> **${RESOLVED_COUNT} resolved investigations** available in \`vault/investigations/resolved/\` — consult these if you encounter a similar problem area. Do NOT read them all; look up specific ones by keyword when relevant." || true
    fi
fi

# --- PRIORITY 2: Load gotchas (relevance-filtered) ---
# First load gotchas relevant to recently changed code, then others if budget allows.
if [ -d "${VAULT_DIR}/gotchas" ]; then
    RELEVANT_GOTCHAS=""
    OTHER_GOTCHAS=""

    for f in "${VAULT_DIR}/gotchas"/*.md; do
        [ -f "$f" ] || continue
        FILENAME=$(basename "$f" .md)
        DESC=$(grep -m1 '^#' "$f" 2>/dev/null | sed 's/^#* *//' || echo "")
        ENTRY="- **${FILENAME}**: ${DESC}"

        # Check if this gotcha is relevant to recently changed areas
        IS_RELEVANT=false
        if [ -n "$CHANGED_DIRS" ]; then
            # Check if the gotcha file mentions any of the changed directories
            for dir in $CHANGED_DIRS; do
                if grep -qi "$(basename "$dir")" "$f" 2>/dev/null; then
                    IS_RELEVANT=true
                    break
                fi
            done
        fi

        if [ "$IS_RELEVANT" = "true" ]; then
            RELEVANT_GOTCHAS="${RELEVANT_GOTCHAS}\n${ENTRY}"
        else
            OTHER_GOTCHAS="${OTHER_GOTCHAS}\n${ENTRY}"
        fi
    done

    GOTCHA_SECTION=""
    if [ -n "$RELEVANT_GOTCHAS" ] || [ -n "$OTHER_GOTCHAS" ]; then
        GOTCHA_SECTION="\n\n## KNOWN GOTCHAS (pitfalls to avoid)"
        if [ -n "$RELEVANT_GOTCHAS" ]; then
            GOTCHA_SECTION="${GOTCHA_SECTION}\n${RELEVANT_GOTCHAS}"
        fi
        if [ -n "$OTHER_GOTCHAS" ]; then
            # Add remaining gotchas only if budget allows
            COMBINED="${GOTCHA_SECTION}\n${OTHER_GOTCHAS}"
            if budget_allows "$COMBINED"; then
                GOTCHA_SECTION="$COMBINED"
            elif [ -z "$RELEVANT_GOTCHAS" ]; then
                # No relevant ones and full list doesn't fit — show count only
                OTHER_COUNT=$(echo -e "$OTHER_GOTCHAS" | grep -c '^\-' || echo "0")
                GOTCHA_SECTION="${GOTCHA_SECTION}\n> ${OTHER_COUNT} gotchas available in \`vault/gotchas/\` — consult when working in unfamiliar areas."
            fi
            # If relevant ones loaded but others don't fit, just skip others
        fi
        add_to_context "$GOTCHA_SECTION" || true
    fi
fi

# --- PRIORITY 3: Load session recovery (if recent) ---
if [ -d "${VAULT_DIR}/session-recovery" ]; then
    RECENT_RECOVERY=$(find "${VAULT_DIR}/session-recovery" -name "20*-*.md" ! -name "summary-*" -mmin -120 -type f 2>/dev/null | sort -r | head -1)
    if [ -n "$RECENT_RECOVERY" ] && [ -f "$RECENT_RECOVERY" ]; then
        RECOVERY_CONTENT=$(head -40 "$RECENT_RECOVERY")
        add_to_context "\n\n## RECENT SESSION RECOVERY (from compaction)\n${RECOVERY_CONTENT}" || true
    fi

    # Check for incomplete session summaries (up to 48 hours old)
    RECENT_SUMMARY=$(find "${VAULT_DIR}/session-recovery" -name "summary-*.md" -mmin -2880 -type f 2>/dev/null | sort -r | head -1)
    if [ -n "$RECENT_SUMMARY" ] && [ -f "$RECENT_SUMMARY" ]; then
        if grep -q "status: incomplete" "$RECENT_SUMMARY" 2>/dev/null; then
            SUMMARY_CONTENT=$(head -40 "$RECENT_SUMMARY")
            add_to_context "\n\n## PREVIOUS SESSION CONTEXT (incomplete work from prior session)\n${SUMMARY_CONTENT}" || true
        fi
    fi
fi

# --- PRIORITY 4: Load high-confidence learned patterns ---
if [ -d "${VAULT_DIR}/patterns/learned" ]; then
    HIGH_CONF_PATTERNS=""
    for f in "${VAULT_DIR}/patterns/learned/"*.md; do
        [ -f "$f" ] || continue
        CONF=$(grep "^confidence:" "$f" 2>/dev/null | head -1 | awk '{print $2}')
        # Guard: skip if CONF is empty or non-numeric (awk would get a syntax error)
        if [ -n "$CONF" ] && echo "$CONF" | grep -qE '^[0-9]+\.?[0-9]*$' && awk "BEGIN {if ($CONF >= 0.7) exit 0; else exit 1}" 2>/dev/null; then
            NAME=$(basename "$f" .md)
            TITLE=$(grep -m1 '^# ' "$f" 2>/dev/null | sed 's/^# //')
            HIGH_CONF_PATTERNS="${HIGH_CONF_PATTERNS}\n- **${NAME}**: ${TITLE} (confidence: ${CONF})"
        fi
    done

    if [ -n "$HIGH_CONF_PATTERNS" ]; then
        add_to_context "\n\n## LEARNED PATTERNS (high confidence)\n${HIGH_CONF_PATTERNS}" || true
    fi
fi

# --- PRIORITY 5: Load recent team activity (lowest priority) ---
if [ -d "${VAULT_DIR}/activity" ]; then
    ACTIVITY=""
    for i in 0 1 2; do
        if [[ "$OSTYPE" == "darwin"* ]]; then
            DAY=$(date -v-${i}d +%Y-%m-%d)
        else
            DAY=$(date -d "-${i} days" +%Y-%m-%d)
        fi
        ACTIVITY_FILE="${VAULT_DIR}/activity/${DAY}.md"
        if [ -f "$ACTIVITY_FILE" ]; then
            ENTRIES=$(tail -10 "$ACTIVITY_FILE" | grep "^- " || echo "")
            if [ -n "$ENTRIES" ]; then
                ACTIVITY="${ACTIVITY}\n### ${DAY}\n${ENTRIES}"
            fi
        fi
    done

    if [ -n "$ACTIVITY" ]; then
        add_to_context "\n\n## RECENT TEAM ACTIVITY (last 3 days)\n${ACTIVITY}" || true
    fi
fi

# --- Team onboarding check (tiny — always fits) ---
MANIFEST_FILE=""
for candidate in "${CWD}/.claude/shared/manifest.json" "${CWD}/templates/shared/manifest.json"; do
    if [ -f "$candidate" ]; then
        MANIFEST_FILE="$candidate"
        break
    fi
done

if [ -n "$MANIFEST_FILE" ]; then
    GIT_USER=$(git -C "$CWD" config user.name 2>/dev/null || echo "")
    if [ -n "$GIT_USER" ]; then
        ONBOARD_MARKER="${CWD}/.sentinel/onboarded-$(echo "$GIT_USER" | tr ' ' '-' | tr '[:upper:]' '[:lower:]')"
        if [ ! -f "$ONBOARD_MARKER" ]; then
            add_to_context "\n\n## TEAM ONBOARDING\nYou haven't completed team onboarding yet. Run \`/sentinel-onboard\` to get set up." || true
        fi
    fi
fi

# --- CLAUDE.md fact checking (runs separately, output is small) ---
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"
FACTS_SCRIPT="${PLUGIN_ROOT}/scripts/check-facts.sh"
if [ -x "$FACTS_SCRIPT" ]; then
    FACTS_OUTPUT=$("$FACTS_SCRIPT" "$CWD" 2>/dev/null || echo "")
    if [ -n "$FACTS_OUTPUT" ]; then
        add_to_context "\n\n## CLAUDE.md FACT CHECK\n${FACTS_OUTPUT}" || true
    fi
fi

# --- Summary counts ---
INVESTIGATION_COUNT=0
GOTCHA_COUNT=0
if [ -d "${VAULT_DIR}/investigations" ]; then
    INVESTIGATION_COUNT=$(find "${VAULT_DIR}/investigations" -maxdepth 1 -name "*.md" ! -name "_template.md" -type f 2>/dev/null | wc -l | tr -d ' ')
fi
if [ -d "${VAULT_DIR}/gotchas" ]; then
    GOTCHA_COUNT=$(find "${VAULT_DIR}/gotchas" -name "*.md" -type f 2>/dev/null | wc -l | tr -d ' ')
fi

# --- Budget reporting ---
TOKENS_USED=$(( CHARS_USED * 10 / 35 ))
BUDGET_NOTE=""
if [ "$TOKENS_USED" -gt "$TOKEN_BUDGET" ]; then
    BUDGET_NOTE=" [over budget: ~${TOKENS_USED}/${TOKEN_BUDGET} tokens]"
fi

# --- Output context for injection into the session ---
if [ -n "$CONTEXT" ]; then
    echo -e "VAULT CONTEXT LOADED (${INVESTIGATION_COUNT} investigations, ${GOTCHA_COUNT} gotchas, ~${TOKENS_USED} tokens):${CONTEXT}\n\nBefore attempting any fix, CHECK vault/investigations/ for past failed approaches. Before writing code, CHECK vault/gotchas/ for known pitfalls."
fi

exit 0

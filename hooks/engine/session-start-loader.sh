#!/bin/bash
# SESSION START HOOK: Load vault context into every new session
#
# Injects critical vault knowledge at session start so the agent is aware of:
# - Open investigations (prevents repeating failed approaches)
# - Known gotchas (prevents known mistakes)
# - Recent session recovery files (enables cross-session continuity)
#
# This is the most important hook — it closes the feedback loop between
# past sessions and the current one.

set -euo pipefail

INPUT=$(cat)
CWD=$(echo "$INPUT" | jq -r '.cwd // empty')

# Resolve vault directory relative to project root
VAULT_DIR="${CWD}/vault"

# Graceful exit if vault doesn't exist — project hasn't adopted vault yet
if [ ! -d "$VAULT_DIR" ]; then
    exit 0
fi

# Build context string to inject into the session
CONTEXT=""

# --- 1. Load open investigations (most critical) ---
# These prevent the agent from repeating approaches that already failed
# in prior sessions.
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
        CONTEXT="${CONTEXT}\n\n## OPEN INVESTIGATIONS (check before attempting fixes)\n${OPEN_INVESTIGATIONS}"
    fi

    # Count resolved investigations without loading them (progressive disclosure)
    RESOLVED_COUNT=0
    if [ -d "${VAULT_DIR}/investigations/resolved" ]; then
        RESOLVED_COUNT=$(find "${VAULT_DIR}/investigations/resolved" -name "*.md" -type f 2>/dev/null | wc -l | tr -d ' ')
    fi
    if [ "$RESOLVED_COUNT" -gt 0 ]; then
        CONTEXT="${CONTEXT}\n\n> **${RESOLVED_COUNT} resolved investigations** in \`vault/investigations/resolved/\` — consult when encountering similar problems."
    fi
fi

# --- 2. Load gotcha filenames with one-line descriptions ---
# These are known pitfalls the agent should be aware of before editing code.
if [ -d "${VAULT_DIR}/gotchas" ]; then
    GOTCHAS=""
    for f in "${VAULT_DIR}/gotchas"/*.md; do
        [ -f "$f" ] || continue
        FILENAME=$(basename "$f" .md)
        # Extract first heading as a brief description
        DESC=$(grep -m1 '^#' "$f" 2>/dev/null | sed 's/^#* *//' || echo "")
        GOTCHAS="${GOTCHAS}\n- **${FILENAME}**: ${DESC}"
    done

    if [ -n "$GOTCHAS" ]; then
        CONTEXT="${CONTEXT}\n\n## KNOWN GOTCHAS (pitfalls to avoid)\n${GOTCHAS}"
    fi
fi

# --- 3. Load most recent session recovery file (from last 2 hours) ---
# Compaction recovery files help the agent resume mid-task after context loss.
if [ -d "${VAULT_DIR}/session-recovery" ]; then
    RECENT_RECOVERY=$(find "${VAULT_DIR}/session-recovery" -name "20*-*.md" ! -name "summary-*" -mmin -120 -type f 2>/dev/null | sort -r | head -1)
    if [ -n "$RECENT_RECOVERY" ] && [ -f "$RECENT_RECOVERY" ]; then
        RECOVERY_CONTENT=$(head -40 "$RECENT_RECOVERY")
        CONTEXT="${CONTEXT}\n\n## RECENT SESSION RECOVERY (from compaction)\n${RECOVERY_CONTENT}"
    fi

    # Also check for incomplete session summaries (up to 48 hours old)
    RECENT_SUMMARY=$(find "${VAULT_DIR}/session-recovery" -name "summary-*.md" -mmin -2880 -type f 2>/dev/null | sort -r | head -1)
    if [ -n "$RECENT_SUMMARY" ] && [ -f "$RECENT_SUMMARY" ]; then
        if grep -q "status: incomplete" "$RECENT_SUMMARY" 2>/dev/null; then
            SUMMARY_CONTENT=$(head -40 "$RECENT_SUMMARY")
            CONTEXT="${CONTEXT}\n\n## PREVIOUS SESSION (incomplete work)\n${SUMMARY_CONTENT}"
        fi
    fi
fi

# --- 4. Load high-confidence learned patterns ---
# Patterns with confidence >= 0.7 are injected as guidance.
if [ -d "${VAULT_DIR}/patterns/learned" ]; then
    HIGH_CONF_PATTERNS=""
    for f in "${VAULT_DIR}/patterns/learned/"*.md; do
        [ -f "$f" ] || continue
        CONF=$(grep "^confidence:" "$f" 2>/dev/null | head -1 | awk '{print $2}')
        # Only load patterns with confidence >= 0.7
        if [ -n "$CONF" ] && [ "$(echo "$CONF >= 0.7" | bc 2>/dev/null || echo 0)" -eq 1 ]; then
            NAME=$(basename "$f" .md)
            TITLE=$(grep -m1 '^# ' "$f" 2>/dev/null | sed 's/^# //')
            HIGH_CONF_PATTERNS="${HIGH_CONF_PATTERNS}\n- **${NAME}**: ${TITLE} (confidence: ${CONF})"
        fi
    done

    if [ -n "$HIGH_CONF_PATTERNS" ]; then
        CONTEXT="${CONTEXT}\n\n## LEARNED PATTERNS (high confidence)\n${HIGH_CONF_PATTERNS}"
    fi
fi

# --- 5. Summary counts ---
INVESTIGATION_COUNT=0
GOTCHA_COUNT=0
if [ -d "${VAULT_DIR}/investigations" ]; then
    INVESTIGATION_COUNT=$(find "${VAULT_DIR}/investigations" -maxdepth 1 -name "*.md" ! -name "_template.md" -type f 2>/dev/null | wc -l | tr -d ' ')
fi
if [ -d "${VAULT_DIR}/gotchas" ]; then
    GOTCHA_COUNT=$(find "${VAULT_DIR}/gotchas" -name "*.md" -type f 2>/dev/null | wc -l | tr -d ' ')
fi

# --- Output context for injection into the session ---
if [ -n "$CONTEXT" ]; then
    echo -e "VAULT CONTEXT LOADED (${INVESTIGATION_COUNT} investigations, ${GOTCHA_COUNT} gotchas):${CONTEXT}\n\nBefore attempting any fix, CHECK vault/investigations/ for past failed approaches. Before writing code, CHECK vault/gotchas/ for known pitfalls."
fi

exit 0

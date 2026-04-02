#!/bin/bash
# SESSION START HOOK: Auto-prune stale vault entries
#
# Runs every 5th session (tracked via .sentinel/session-count).
# Three tiers:
#   Tier 1 (auto-archive): Silently moves clearly stale entries to vault/.archive/
#   Tier 2 (auto-flag): Outputs warnings for ambiguous entries that need human review
#   Tier 3 (manual): Deep cleanup via /sentinel prune command (not in this hook)
#
# NEVER deletes — always archives to vault/.archive/ with original directory structure.
# If someone needs something back, it's still there.

set -euo pipefail

INPUT=$(cat)
CWD=$(echo "$INPUT" | jq -r '.cwd // empty')

[ -z "$CWD" ] && exit 0

VAULT_DIR="${CWD}/vault"
SENTINEL_DIR="${CWD}/.sentinel"

# Graceful exit if vault doesn't exist
if [ ! -d "$VAULT_DIR" ]; then
    exit 0
fi

# --- Session counter: only run every 5th session ---
mkdir -p "$SENTINEL_DIR" 2>/dev/null || true
COUNT_FILE="${SENTINEL_DIR}/session-count"

COUNT=0
if [ -f "$COUNT_FILE" ]; then
    COUNT=$(cat "$COUNT_FILE" 2>/dev/null || echo "0")
fi
COUNT=$((COUNT + 1))
echo "$COUNT" > "$COUNT_FILE"

# Run pruning on sessions 5, 10, 15, ...
if [ $((COUNT % 5)) -ne 0 ]; then
    exit 0
fi

# --- Setup archive directory ---
ARCHIVE_DIR="${VAULT_DIR}/.archive"
NOW_EPOCH=$(date +%s)
ARCHIVED=0
FLAGS=""

# Helper: get file age in days (cross-platform)
file_age_days() {
    local file="$1"
    local mtime
    if [[ "$OSTYPE" == "darwin"* ]]; then
        mtime=$(stat -f %m "$file" 2>/dev/null || echo "$NOW_EPOCH")
    else
        mtime=$(stat -c %Y "$file" 2>/dev/null || echo "$NOW_EPOCH")
    fi
    echo $(( (NOW_EPOCH - mtime) / 86400 ))
}

# Helper: archive a file preserving directory structure
archive_file() {
    local file="$1"
    local rel_path="${file#${VAULT_DIR}/}"
    local dest_dir="${ARCHIVE_DIR}/$(dirname "$rel_path")"
    mkdir -p "$dest_dir" 2>/dev/null || true
    mv "$file" "${dest_dir}/$(basename "$file")" 2>/dev/null || true
    ARCHIVED=$((ARCHIVED + 1))
}

# ============================================================
# TIER 1: Auto-archive (silent, clearly stale)
# ============================================================

# --- 1a. Session recovery files >7 days old ---
if [ -d "${VAULT_DIR}/session-recovery" ]; then
    while read -r file; do
        age=$(file_age_days "$file")
        if [ "$age" -gt 7 ]; then
            archive_file "$file"
        fi
    done < <(find "${VAULT_DIR}/session-recovery" -name "*.md" -type f 2>/dev/null)
fi

# --- 1b. Resolved investigations >30 days old ---
if [ -d "${VAULT_DIR}/investigations/resolved" ]; then
    while read -r file; do
        [ "$(basename "$file")" = "_template.md" ] && continue
        age=$(file_age_days "$file")
        if [ "$age" -gt 30 ]; then
            archive_file "$file"
        fi
    done < <(find "${VAULT_DIR}/investigations/resolved" -name "*.md" -type f 2>/dev/null)
fi

# --- 1c. Changelog entries >90 days old ---
if [ -d "${VAULT_DIR}/changelog" ]; then
    while read -r file; do
        age=$(file_age_days "$file")
        if [ "$age" -gt 90 ]; then
            archive_file "$file"
        fi
    done < <(find "${VAULT_DIR}/changelog" -name "*.md" -type f 2>/dev/null)
fi

# --- 1d. Decisions with status "superseded" or "deprecated" ---
if [ -d "${VAULT_DIR}/decisions" ]; then
    while read -r file; do
        [ "$(basename "$file")" = "_template.md" ] && continue
        status=$(awk '/^---$/{n++; next} n==1 && /^status:/{gsub(/^status: */, ""); print; exit}' "$file" 2>/dev/null || echo "")
        if [ "$status" = "superseded" ] || [ "$status" = "deprecated" ]; then
            archive_file "$file"
        fi
    done < <(find "${VAULT_DIR}/decisions" -name "*.md" -type f 2>/dev/null)
fi

# --- 1e. Activity feed files >30 days old ---
if [ -d "${VAULT_DIR}/activity" ]; then
    while read -r file; do
        age=$(file_age_days "$file")
        if [ "$age" -gt 30 ]; then
            archive_file "$file"
        fi
    done < <(find "${VAULT_DIR}/activity" -name "*.md" -type f 2>/dev/null)
fi

# --- 1f. Empty directories (cleanup) ---
find "$VAULT_DIR" -type d -empty -not -path "${ARCHIVE_DIR}/*" -not -path "$VAULT_DIR" -delete 2>/dev/null || true

# ============================================================
# TIER 2: Auto-flag (output warnings for human review)
# ============================================================

# --- 2a. Gotchas referencing deleted files ---
if [ -d "${VAULT_DIR}/gotchas" ]; then
    PROJECT_ROOT=$(dirname "$VAULT_DIR")
    for f in "${VAULT_DIR}/gotchas"/*.md; do
        [ -f "$f" ] || continue
        [ "$(basename "$f")" = "_template.md" ] && continue
        [ "$(basename "$f")" = "_example.md" ] && continue

        # Extract file paths mentioned in the gotcha
        refs=$(grep -oE '(src|tests|lib|app|packages)/[a-zA-Z0-9_./-]+\.(py|tsx?|jsx?|go|rs|java|rb|swift|kt)' "$f" 2>/dev/null | sort -u || echo "")
        [ -z "$refs" ] && continue

        all_dead=true
        while IFS= read -r ref; do
            [ -z "$ref" ] && continue
            if [ -f "${PROJECT_ROOT}/${ref}" ]; then
                all_dead=false
                break
            fi
        done <<< "$refs"

        if [ "$all_dead" = true ]; then
            FLAGS="${FLAGS}\n  - $(basename "$f"): all referenced files have been deleted — review or archive"
        fi
    done
fi

# --- 2b. Open investigations >60 days old ---
if [ -d "${VAULT_DIR}/investigations" ]; then
    for f in "${VAULT_DIR}/investigations"/*.md; do
        [ -f "$f" ] || continue
        [ "$(basename "$f")" = "_template.md" ] && continue

        # Skip if resolved
        if grep -qi "status:.*\(resolved\|implemented\|obsolete\)" "$f" 2>/dev/null; then
            continue
        fi

        age=$(file_age_days "$f")
        if [ "$age" -gt 60 ]; then
            FLAGS="${FLAGS}\n  - $(basename "$f"): open for ${age} days — resolve, abandon, or update"
        fi
    done
fi

# --- 2c. Learned patterns with zero observations in 30+ days ---
if [ -d "${VAULT_DIR}/patterns/learned" ]; then
    for f in "${VAULT_DIR}/patterns/learned"/*.md; do
        [ -f "$f" ] || continue
        age=$(file_age_days "$f")
        if [ "$age" -gt 30 ]; then
            obs=$(grep "^observations:" "$f" 2>/dev/null | head -1 | awk '{print $2}')
            if [ -n "$obs" ] && [ "$obs" -eq 0 ] 2>/dev/null; then
                FLAGS="${FLAGS}\n  - $(basename "$f"): 0 observations in ${age} days — still relevant?"
            fi
        fi
    done
fi

# ============================================================
# OUTPUT
# ============================================================

OUTPUT=""

if [ "$ARCHIVED" -gt 0 ]; then
    OUTPUT="VAULT PRUNE: Archived ${ARCHIVED} stale entry(ies) to vault/.archive/"
fi

if [ -n "$FLAGS" ]; then
    if [ -n "$OUTPUT" ]; then
        OUTPUT="${OUTPUT}\n"
    fi
    OUTPUT="${OUTPUT}VAULT PRUNE — review needed:${FLAGS}"
fi

if [ -n "$OUTPUT" ]; then
    echo -e "$OUTPUT"
fi

exit 0

#!/bin/bash
# VAULT DEEP CLEANUP: Identifies and cleans stale vault content.
#
# Checks:
# 1. Session recovery files older than 7 days (delete)
# 2. Changelog entries older than 30 days (archive)
# 3. Resolved investigations not referenced in 30+ days (suggest archive)
# 4. Empty directories (report)
# 5. Duplicate gotchas by title (report)
#
# Usage: vault-prune.sh <vault_dir> [--dry-run]
#
# --dry-run: Show what would be done without making changes

set -euo pipefail

VAULT_DIR="${1:?Usage: vault-prune.sh <vault_dir> [--dry-run]}"
DRY_RUN=false
if [ "${2:-}" = "--dry-run" ]; then
    DRY_RUN=true
    echo "=== DRY RUN MODE ==="
    echo ""
fi

ACTIONS_TAKEN=0
ISSUES_FOUND=0

# --- 1. Session recovery files older than 7 days ---
echo "--- Checking session recovery files (>7 days old) ---"
SESSION_DIR="${VAULT_DIR}/session-logs"
if [ -d "$SESSION_DIR" ]; then
    find "$SESSION_DIR" -name "*.md" -type f -mtime +7 2>/dev/null | while read -r file; do
        ISSUES_FOUND=$((ISSUES_FOUND + 1))
        if [ "$DRY_RUN" = true ]; then
            echo "  WOULD DELETE: $file"
        else
            rm "$file"
            echo "  DELETED: $file"
            ACTIONS_TAKEN=$((ACTIONS_TAKEN + 1))
        fi
    done
else
    echo "  No session-logs/ directory found — skipping"
fi
echo ""

# --- 2. Changelog entries older than 30 days ---
echo "--- Checking changelog entries (>30 days old) ---"
CHANGELOG_DIR="${VAULT_DIR}/changelog"
ARCHIVE_DIR="${VAULT_DIR}/changelog/archive"
if [ -d "$CHANGELOG_DIR" ]; then
    find "$CHANGELOG_DIR" -maxdepth 1 -name "*.md" -type f -mtime +30 2>/dev/null | while read -r file; do
        filename=$(basename "$file")
        # Skip templates
        [ "$filename" = "_template.md" ] && continue

        ISSUES_FOUND=$((ISSUES_FOUND + 1))
        if [ "$DRY_RUN" = true ]; then
            echo "  WOULD ARCHIVE: $file → ${ARCHIVE_DIR}/${filename}"
        else
            mkdir -p "$ARCHIVE_DIR"
            mv "$file" "${ARCHIVE_DIR}/${filename}"
            echo "  ARCHIVED: $file → ${ARCHIVE_DIR}/${filename}"
            ACTIONS_TAKEN=$((ACTIONS_TAKEN + 1))
        fi
    done
else
    echo "  No changelog/ directory found — skipping"
fi
echo ""

# --- 3. Resolved investigations not referenced in 30+ days ---
echo "--- Checking resolved investigations (>30 days since last modified) ---"
INVESTIGATIONS_DIR="${VAULT_DIR}/investigations"
if [ -d "$INVESTIGATIONS_DIR" ]; then
    # Check both resolved/ subdirectory and files with "status: resolved" in frontmatter
    find "$INVESTIGATIONS_DIR" -name "*.md" -type f -mtime +30 2>/dev/null | while read -r file; do
        filename=$(basename "$file")
        [ "$filename" = "_template.md" ] && continue

        # Check if this is a resolved investigation
        is_resolved=false

        # Check if in resolved/ subdirectory
        if echo "$file" | grep -q "/resolved/"; then
            is_resolved=true
        fi

        # Check frontmatter for status: resolved
        if grep -q "^status: *resolved" "$file" 2>/dev/null; then
            is_resolved=true
        fi

        if [ "$is_resolved" = true ]; then
            ISSUES_FOUND=$((ISSUES_FOUND + 1))
            echo "  SUGGEST ARCHIVE: $file (resolved, not modified in 30+ days)"
        fi
    done
else
    echo "  No investigations/ directory found — skipping"
fi
echo ""

# --- 4. Empty directories ---
echo "--- Checking for empty directories ---"
find "$VAULT_DIR" -type d -empty 2>/dev/null | while read -r dir; do
    # Skip hidden directories
    case "$dir" in
        */.git*) continue ;;
    esac
    ISSUES_FOUND=$((ISSUES_FOUND + 1))
    echo "  EMPTY DIR: $dir"
done
echo ""

# --- 5. Duplicate gotchas (same title) ---
echo "--- Checking for duplicate gotchas ---"
GOTCHAS_DIR="${VAULT_DIR}/gotchas"
if [ -d "$GOTCHAS_DIR" ]; then
    # Extract titles and find duplicates
    TITLES_TMP=$(mktemp)
    trap "rm -f '$TITLES_TMP'" EXIT

    find "$GOTCHAS_DIR" -name "*.md" -type f 2>/dev/null | while read -r file; do
        filename=$(basename "$file")
        [ "$filename" = "_template.md" ] && continue

        title=$(awk '
            /^---$/ { fm++; next }
            fm >= 2 && /^#/ { gsub(/^#+ */, ""); print; exit }
            fm < 2 && /^#/ { gsub(/^#+ */, ""); print; exit }
        ' "$file" 2>/dev/null || echo "")

        if [ -n "$title" ]; then
            echo "${title}|||${file}" >> "$TITLES_TMP"
        fi
    done

    if [ -s "$TITLES_TMP" ]; then
        # Find duplicate titles
        sort -t'|' -k1,1 "$TITLES_TMP" | awk -F'\\|\\|\\|' '
            {
                title = $1
                file = $2
                if (title == prev_title && title != "") {
                    if (!printed_first) {
                        printf "  DUPLICATE TITLE: \"%s\"\n    - %s\n", title, prev_file
                        printed_first = 1
                    }
                    printf "    - %s\n", file
                } else {
                    printed_first = 0
                }
                prev_title = title
                prev_file = file
            }
        '
    fi

    rm -f "$TITLES_TMP"
else
    echo "  No gotchas/ directory found — skipping"
fi
echo ""

# --- Summary ---
echo "=== Vault Prune Complete ==="
if [ "$DRY_RUN" = true ]; then
    echo "Dry run — no changes made. Re-run without --dry-run to apply."
fi

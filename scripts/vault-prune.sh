#!/bin/bash
# VAULT PRUNE: Finds stale vault entries and outputs a report.
# Does NOT auto-delete -- human review required.
#
# Checks:
# 1. Investigations >90 days old and still open
# 2. Gotchas referencing deleted files
# 3. Decisions with status "superseded"
#
# Usage: vault-prune.sh <vault_dir> [--project-root <root>]
#
# --project-root: Project root directory for checking file references (default: parent of vault_dir)

set -euo pipefail

VAULT_DIR="${1:?Usage: vault-prune.sh <vault_dir> [--project-root <root>]}"
PROJECT_ROOT=""

# Parse optional args
shift
while [ $# -gt 0 ]; do
    case "$1" in
        --project-root)
            PROJECT_ROOT="${2:?Missing project root path}"
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Default project root to parent of vault dir
if [ -z "$PROJECT_ROOT" ]; then
    PROJECT_ROOT=$(dirname "$VAULT_DIR")
fi

ISSUES_FOUND=0

echo "=== Vault Prune Report ==="
echo "Vault: ${VAULT_DIR}"
echo "Project root: ${PROJECT_ROOT}"
echo ""

# --- 1. Open investigations >90 days old ---
echo "--- Open investigations older than 90 days ---"
INVESTIGATIONS_DIR="${VAULT_DIR}/investigations"
if [ -d "$INVESTIGATIONS_DIR" ]; then
    find "$INVESTIGATIONS_DIR" -name "*.md" -type f 2>/dev/null | while read -r file; do
        filename=$(basename "$file")
        [ "$filename" = "_template.md" ] && continue

        # Skip if in resolved/ subdirectory
        echo "$file" | grep -q "/resolved/" && continue

        # Check if status is still open or in-progress
        status=$(awk '/^---$/{n++; next} n==1 && /^status:/{gsub(/^status: */, ""); print; exit}' "$file" 2>/dev/null || echo "")

        case "$status" in
            open|in-progress|"")
                # Check file age
                if [[ "$OSTYPE" == "darwin"* ]]; then
                    file_age_days=$(( ($(date +%s) - $(stat -f %m "$file")) / 86400 ))
                else
                    file_age_days=$(( ($(date +%s) - $(stat -c %Y "$file")) / 86400 ))
                fi

                if [ "$file_age_days" -gt 90 ]; then
                    ISSUES_FOUND=$((ISSUES_FOUND + 1))
                    echo "  STALE: $file"
                    echo "         Status: ${status:-unknown}, Age: ${file_age_days} days"
                    echo "         Action: Resolve, abandon, or update this investigation"
                fi
                ;;
        esac
    done
else
    echo "  No investigations/ directory found"
fi
echo ""

# --- 2. Gotchas referencing deleted files ---
echo "--- Gotchas referencing deleted files ---"
GOTCHAS_DIR="${VAULT_DIR}/gotchas"
if [ -d "$GOTCHAS_DIR" ]; then
    find "$GOTCHAS_DIR" -name "*.md" -type f 2>/dev/null | while read -r file; do
        filename=$(basename "$file")
        [ "$filename" = "_template.md" ] && continue
        [ "$filename" = "_example.md" ] && continue

        # Extract file paths mentioned in the gotcha
        referenced_files=$(grep -oE '(src|tests|lib|app)/[a-zA-Z0-9_./-]+\.(py|tsx?|js|go|rs|java)' "$file" 2>/dev/null | sort -u || echo "")

        if [ -n "$referenced_files" ]; then
            echo "$referenced_files" | while read -r ref_file; do
                [ -z "$ref_file" ] && continue
                if [ ! -f "${PROJECT_ROOT}/${ref_file}" ]; then
                    ISSUES_FOUND=$((ISSUES_FOUND + 1))
                    echo "  DEAD REF: $file"
                    echo "            References: ${ref_file} (file does not exist)"
                    echo "            Action: Update or delete this gotcha"
                fi
            done
        fi
    done
else
    echo "  No gotchas/ directory found"
fi
echo ""

# --- 3. Decisions with status "superseded" ---
echo "--- Superseded decisions ---"
DECISIONS_DIR="${VAULT_DIR}/decisions"
if [ -d "$DECISIONS_DIR" ]; then
    find "$DECISIONS_DIR" -name "*.md" -type f 2>/dev/null | while read -r file; do
        filename=$(basename "$file")
        [ "$filename" = "_template.md" ] && continue

        status=$(awk '/^---$/{n++; next} n==1 && /^status:/{gsub(/^status: */, ""); print; exit}' "$file" 2>/dev/null || echo "")

        if [ "$status" = "superseded" ] || [ "$status" = "deprecated" ]; then
            ISSUES_FOUND=$((ISSUES_FOUND + 1))
            title=$(awk '
                /^---$/ { fm++; next }
                fm >= 2 && /^#/ { gsub(/^#+ */, ""); print; exit }
            ' "$file" 2>/dev/null || echo "$filename")
            echo "  SUPERSEDED: $file"
            echo "              Title: ${title}"
            echo "              Action: Archive or remove if no longer referenced"
        fi
    done
else
    echo "  No decisions/ directory found"
fi
echo ""

# --- Summary ---
echo "=== Summary ==="
echo "Issues found: ${ISSUES_FOUND}"
if [ "$ISSUES_FOUND" -eq 0 ]; then
    echo "Vault is clean -- no stale entries found."
else
    echo "Review the items above and take action manually."
    echo "This script does NOT auto-delete -- all changes require human review."
fi

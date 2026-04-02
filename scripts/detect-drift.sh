#!/bin/bash
# DRIFT DETECTION: Find architecture docs that reference changed/deleted files
#
# Scans vault/architecture/ docs for file path references (src/..., tests/..., etc.)
# Cross-references against actual filesystem to find:
#   1. Docs referencing files that no longer exist (deleted/renamed)
#   2. Docs referencing directories that had structural changes (files added/deleted)
#
# Called by stop-enforcer.sh when source files were modified in the session.
# Outputs a list of stale docs that need updating.
#
# Usage: ./detect-drift.sh <project-root> [modified-files-list]

set -euo pipefail

PROJECT_ROOT="${1:-.}"
MODIFIED_FILES_PATH="${2:-}"
VAULT_DIR="${PROJECT_ROOT}/vault"
ARCH_DIR="${VAULT_DIR}/architecture"

# Exit silently if no architecture docs exist
if [ ! -d "$ARCH_DIR" ]; then
    exit 0
fi

# Collect modified directories from this session
MODIFIED_DIRS=""
if [ -n "$MODIFIED_FILES_PATH" ] && [ -f "$MODIFIED_FILES_PATH" ]; then
    # Extract unique parent directories of modified source files
    MODIFIED_DIRS=$(grep -E '\.(py|tsx?|jsx?|go|rs|rb|java|swift|kt|css|scss)$' "$MODIFIED_FILES_PATH" 2>/dev/null \
        | xargs -I{} dirname {} 2>/dev/null \
        | sort -u || echo "")
fi

STALE_DOCS=""

# Check each architecture doc for dead references
find "$ARCH_DIR" -name "*.md" -type f 2>/dev/null | while read -r doc; do
    DOC_REL="${doc#${VAULT_DIR}/}"
    DEAD_REFS=""
    DRIFT_DIRS=""

    # Extract file path references from the doc
    # Matches patterns like src/..., tests/..., lib/..., app/..., packages/...
    REFS=$(grep -oE '(src|tests|lib|app|packages|strique-[a-z-]+)/[a-zA-Z0-9_./-]+\.(py|tsx?|jsx?|go|rs|java|rb|swift|kt|sh|json|toml|yaml|yml|md)' "$doc" 2>/dev/null | sort -u || echo "")

    if [ -z "$REFS" ]; then
        continue
    fi

    # Check each referenced file
    while IFS= read -r ref; do
        [ -z "$ref" ] && continue

        # Check if the referenced file still exists
        if [ ! -f "${PROJECT_ROOT}/${ref}" ]; then
            DEAD_REFS="${DEAD_REFS}\n    - \`${ref}\` no longer exists"
        fi
    done <<< "$REFS"

    # Check if any modified directories overlap with directories mentioned in this doc
    if [ -n "$MODIFIED_DIRS" ]; then
        # Extract directory references from the doc
        DOC_DIRS=$(grep -oE '(src|tests|lib|app|packages|strique-[a-z-]+)/[a-zA-Z0-9_/-]+/' "$doc" 2>/dev/null | sort -u || echo "")

        while IFS= read -r doc_dir; do
            [ -z "$doc_dir" ] && continue
            # Check if any modified directory starts with this doc directory
            if echo "$MODIFIED_DIRS" | grep -q "${PROJECT_ROOT}/${doc_dir}" 2>/dev/null; then
                DRIFT_DIRS="${DRIFT_DIRS}\n    - \`${doc_dir}\` had files modified this session"
            fi
        done <<< "$DOC_DIRS"
    fi

    # Report findings for this doc
    if [ -n "$DEAD_REFS" ] || [ -n "$DRIFT_DIRS" ]; then
        echo "  - **${DOC_REL}**:"
        if [ -n "$DEAD_REFS" ]; then
            echo -e "    Dead references:${DEAD_REFS}"
        fi
        if [ -n "$DRIFT_DIRS" ]; then
            echo -e "    Modified areas:${DRIFT_DIRS}"
        fi
    fi
done

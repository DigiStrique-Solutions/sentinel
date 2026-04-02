#!/bin/bash
# GIT MERGE DRIVER: Concatenate vault markdown files on conflict
#
# Registered via .gitattributes: vault/**/*.md merge=sentinel-vault
# Configured via: git config merge.sentinel-vault.driver "path/to/vault-merge-driver.sh %O %A %B"
#
# Arguments (standard git merge driver interface):
#   %O = ancestor (base) version
#   %A = current (ours) version — this file gets OVERWRITTEN with the result
#   %B = other (theirs) version
#
# Strategy:
#   - If both sides only added content: concatenate both additions
#   - If one side deleted and the other edited: keep the edit
#   - Deduplicate identical lines
#   - Add merge marker comment when both sides contributed

set -euo pipefail

ANCESTOR="$1"  # %O — base version
OURS="$2"      # %A — current version (result goes here)
THEIRS="$3"    # %B — other version

# If theirs is empty or identical to ours, nothing to do
if [ ! -s "$THEIRS" ] || diff -q "$OURS" "$THEIRS" &>/dev/null; then
    exit 0
fi

# If ours is empty, take theirs
if [ ! -s "$OURS" ]; then
    cp "$THEIRS" "$OURS"
    exit 0
fi

# Try standard git merge first (handles simple cases)
if git merge-file -p "$OURS" "$ANCESTOR" "$THEIRS" > "${OURS}.merged" 2>/dev/null; then
    mv "${OURS}.merged" "$OURS"
    exit 0
fi

# Standard merge failed — use concatenation strategy
rm -f "${OURS}.merged" 2>/dev/null || true

# Extract the header (first line starting with #) from ours
HEADER=$(head -1 "$OURS")

# Get content lines (skip header and empty lines after it) from both
OURS_CONTENT=$(tail -n +2 "$OURS" | sed '/^$/d; /^#/d')
THEIRS_CONTENT=$(tail -n +2 "$THEIRS" | sed '/^$/d; /^#/d')

# Build the merged file
{
    echo "$HEADER"
    echo ""

    # Add ours content
    if [ -n "$OURS_CONTENT" ]; then
        echo "$OURS_CONTENT"
    fi

    # Add theirs content (deduplicate lines already in ours)
    if [ -n "$THEIRS_CONTENT" ]; then
        while IFS= read -r line; do
            # Skip if this exact line already exists in ours
            if ! echo "$OURS_CONTENT" | grep -qFx "$line" 2>/dev/null; then
                echo "$line"
            fi
        done <<< "$THEIRS_CONTENT"
    fi

    echo ""
    echo "<!-- MERGE: review needed — content from multiple authors was combined -->"
} > "$OURS"

exit 0

#!/bin/bash
# BUILD VAULT INDEX: Scans all vault markdown files and produces vault/.index.json
# Maps tags, file paths, and keywords to vault entries for fast lookup.
#
# Performance target: <1.5s for ~110 vault files
#
# Usage: build-index.sh <vault_dir>

set -euo pipefail

VAULT_DIR="${1:?Usage: build-index.sh <vault_dir>}"
INDEX_FILE="${VAULT_DIR}/.index.json"
STALE_MARKER="${VAULT_DIR}/.index-stale"

# Remove stale marker if present
rm -f "$STALE_MARKER" 2>/dev/null || true

# Directories to index (relative to vault/)
SEARCH_DIRS="gotchas investigations decisions completed workflows patterns"

# Temp files for building JSON
ENTRIES_TMP=$(mktemp)
TAGS_TMP=$(mktemp)
FILES_TMP=$(mktemp)

trap "rm -f '$ENTRIES_TMP' '$TAGS_TMP' '$FILES_TMP'" EXIT

# Process each markdown file
for dir in $SEARCH_DIRS; do
    search_path="${VAULT_DIR}/${dir}"
    [ -d "$search_path" ] || continue

    # Include subdirectories (e.g., resolved/ for investigations)
    find "$search_path" -name "*.md" -type f 2>/dev/null | while read -r filepath; do
        filename=$(basename "$filepath")
        # Skip templates
        [ "$filename" = "_template.md" ] && continue

        # Relative path from vault root
        rel_path="${filepath#${VAULT_DIR}/}"

        # Get modification time (macOS stat; Linux: stat -c %Y)
        mtime=$(stat -f %m "$filepath" 2>/dev/null || stat -c %Y "$filepath" 2>/dev/null || echo "0")

        # Extract title: first # line after frontmatter
        title=$(awk '
            /^---$/ { fm++; next }
            fm >= 2 && /^#/ { gsub(/^#+ */, ""); print; exit }
            fm < 2 && /^#/ { gsub(/^#+ */, ""); print; exit }
        ' "$filepath" 2>/dev/null || echo "")

        # Extract tags from frontmatter and body
        tags=""
        # Frontmatter tags (area: or tags: field)
        ft=$(awk '/^---$/{n++; next} n==1 && /^(area|tags):/{gsub(/^[a-z]+: */, ""); print}' "$filepath" 2>/dev/null || echo "")
        if [ -n "$ft" ]; then
            tags=$(echo "$ft" | tr ',;' '\n' | sed 's/^ *//;s/ *$//;s/ /-/g;s/\[//g;s/\]//g' | tr '[:upper:]' '[:lower:]' | grep -v '^$' || echo "")
        fi

        # Inline #hashtags (from body, not frontmatter)
        body_tags=$(awk '/^---$/{n++; next} n>=2{print}' "$filepath" 2>/dev/null | \
            grep -oE '#[a-zA-Z][a-zA-Z0-9_-]+' | sed 's/^#//;y/ABCDEFGHIJKLMNOPQRSTUVWXYZ/abcdefghijklmnopqrstuvwxyz/' | sort -u || echo "")
        if [ -n "$body_tags" ]; then
            tags=$(printf "%s\n%s" "$tags" "$body_tags" | sort -u | grep -v '^$')
        fi

        # **Tags:** line pattern
        explicit_tags=$(grep -oE '\*\*Tags:\*\* .*' "$filepath" 2>/dev/null | \
            sed 's/\*\*Tags:\*\* //' | tr ',;' '\n' | \
            grep -oE '#[a-zA-Z][a-zA-Z0-9_-]+' | sed 's/^#//;y/ABCDEFGHIJKLMNOPQRSTUVWXYZ/abcdefghijklmnopqrstuvwxyz/' || echo "")
        if [ -n "$explicit_tags" ]; then
            tags=$(printf "%s\n%s" "$tags" "$explicit_tags" | sort -u | grep -v '^$')
        fi

        # Extract source file paths mentioned in the file
        files_mentioned=$(grep -oE '(src|tests|lib|app)/[a-zA-Z0-9_./-]+\.(py|tsx?|js|md)' "$filepath" 2>/dev/null | sort -u | head -10 || echo "")

        # Also check backtick-wrapped paths
        bt_files=$(grep -oE '`(src|tests|lib)/[a-zA-Z0-9_./-]+`' "$filepath" 2>/dev/null | tr -d '`' | sort -u | head -5 || echo "")
        if [ -n "$bt_files" ]; then
            files_mentioned=$(printf "%s\n%s" "$files_mentioned" "$bt_files" | sort -u | head -10)
        fi

        # Build tags JSON array
        tags_json="[]"
        if [ -n "$tags" ]; then
            tags_json=$(echo "$tags" | jq -R . | jq -s . 2>/dev/null || echo "[]")
        fi

        # Build files_mentioned JSON array
        files_json="[]"
        if [ -n "$files_mentioned" ]; then
            files_json=$(echo "$files_mentioned" | jq -R . | jq -s . 2>/dev/null || echo "[]")
        fi

        # Escape title for JSON
        title_json=$(echo "$title" | jq -R . 2>/dev/null || echo '""')

        # Write entry
        echo "{\"key\": $(echo "$rel_path" | jq -R .), \"title\": $title_json, \"mtime\": $mtime, \"tags\": $tags_json, \"files_mentioned\": $files_json}" >> "$ENTRIES_TMP"

        # Write tag-to-entry mappings
        if [ -n "$tags" ]; then
            echo "$tags" | while read -r tag; do
                [ -z "$tag" ] && continue
                echo "{\"tag\": $(echo "$tag" | jq -R .), \"entry\": $(echo "$rel_path" | jq -R .)}" >> "$TAGS_TMP"
            done
        fi

        # Write file-to-entry mappings (grouped by directory)
        if [ -n "$files_mentioned" ]; then
            echo "$files_mentioned" | while read -r src_file; do
                [ -z "$src_file" ] && continue
                src_dir=$(dirname "$src_file")/
                echo "{\"dir\": $(echo "$src_dir" | jq -R .), \"entry\": $(echo "$rel_path" | jq -R .)}" >> "$FILES_TMP"
            done
        fi
    done
done

# Assemble the final index JSON
# 1. Build entries object (key -> {title, mtime, tags, files_mentioned})
ENTRIES_JSON="{}"
if [ -s "$ENTRIES_TMP" ]; then
    ENTRIES_JSON=$(jq -s 'map({(.key): {title: .title, mtime: .mtime, tags: .tags, files_mentioned: .files_mentioned}}) | add // {}' "$ENTRIES_TMP" 2>/dev/null || echo "{}")
fi

# 2. Build tags object (tag -> [entries])
TAGS_JSON="{}"
if [ -s "$TAGS_TMP" ]; then
    TAGS_JSON=$(jq -s 'group_by(.tag) | map({(.[0].tag): [.[].entry] | unique}) | add // {}' "$TAGS_TMP" 2>/dev/null || echo "{}")
fi

# 3. Build files object (dir -> [entries])
FILES_JSON="{}"
if [ -s "$FILES_TMP" ]; then
    FILES_JSON=$(jq -s 'group_by(.dir) | map({(.[0].dir): [.[].entry] | unique}) | add // {}' "$FILES_TMP" 2>/dev/null || echo "{}")
fi

# 4. Combine into final index
jq -n --argjson tags "$TAGS_JSON" --argjson files "$FILES_JSON" --argjson entries "$ENTRIES_JSON" \
    '{tags: $tags, files: $files, entries: $entries}' > "$INDEX_FILE"

echo "Vault index built: $(jq '.entries | length' "$INDEX_FILE") entries"

#!/bin/bash
# POST-TOOL HOOK: Detect potentially stale gotchas when source files are edited.
# When a source file is edited, check if any gotcha mentions that file path or module.
# If the gotcha is older than the current edit, warn about potential staleness.
#
# Noise prevention:
# - Skip vault files (editing a gotcha is updating, not invalidating)
# - Skip test files (test changes rarely invalidate gotchas)
# - Only flag entries >1 hour old (prevents same-session false flags)
# - Cap at 3 matches

set -euo pipefail

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.filePath // empty')
CWD=$(echo "$INPUT" | jq -r '.cwd // empty')

# Exit early if no file path
if [ -z "$FILE_PATH" ] || [ -z "$CWD" ]; then
    exit 0
fi

# Skip vault files (editing a gotcha is updating it, not invalidating it)
if echo "$FILE_PATH" | grep -q "vault/"; then
    exit 0
fi

# Skip test files (test changes rarely invalidate gotchas)
if echo "$FILE_PATH" | grep -qE '(test_|_test\.|\.test\.|\.spec\.|/tests/)'; then
    exit 0
fi

# Skip non-source files (config, docs, etc.)
if ! echo "$FILE_PATH" | grep -qE '\.(py|tsx?|jsx?|ts|js|css|scss|sh|go|rs|rb|java|swift|kt)$'; then
    exit 0
fi

VAULT_DIR="${CWD}/vault"

# Graceful exit if vault or gotchas don't exist
if [ ! -d "${VAULT_DIR}/gotchas" ]; then
    exit 0
fi

REL_PATH=$(echo "$FILE_PATH" | sed "s|${CWD}/||")
REL_DIR=$(dirname "$REL_PATH")/
NOW=$(date +%s)
STALE_MATCHES=""
MATCH_COUNT=0

# Grep gotcha files for the directory prefix or filename
for f in "${VAULT_DIR}/gotchas/"*.md; do
    [ -f "$f" ] || continue
    [ "$MATCH_COUNT" -ge 3 ] && break
    [ "$(basename "$f")" = "_template.md" ] && continue

    if grep -ql "$REL_DIR" "$f" 2>/dev/null || grep -ql "$(basename "$REL_PATH")" "$f" 2>/dev/null; then
        # Cross-platform mtime: macOS uses -f, Linux uses -c
        if [[ "$OSTYPE" == "darwin"* ]]; then
            ENTRY_MTIME=$(stat -f %m "$f" 2>/dev/null || echo "0")
        else
            ENTRY_MTIME=$(stat -c %Y "$f" 2>/dev/null || echo "0")
        fi
        AGE=$((NOW - ENTRY_MTIME))
        [ "$AGE" -lt 3600 ] && continue

        DAYS_OLD=$((AGE / 86400))
        ENTRY_TITLE=$(grep -m1 '^#' "$f" 2>/dev/null | sed 's/^#* *//' || echo "(untitled)")
        STALE_MATCHES="${STALE_MATCHES}\n- **$(basename "$f")**: ${ENTRY_TITLE} — last updated ${DAYS_OLD} days ago"
        MATCH_COUNT=$((MATCH_COUNT + 1))
    fi
done

if [ -n "$STALE_MATCHES" ]; then
    echo -e "STALENESS CHECK: Editing $(basename "$FILE_PATH") — these vault entries reference this area and may need updating:${STALE_MATCHES}"
fi

exit 0

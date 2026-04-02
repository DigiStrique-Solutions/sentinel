#!/bin/bash
# POST-TOOL HOOK (optional): Remind about design review after frontend file edits
#
# After editing .tsx, .css, or .scss files (excluding test files), outputs a
# one-line reminder to run a design review before completing the task.
# This is a lightweight nudge, not a blocking check.

set -euo pipefail

INPUT=$(cat)

# Extract file path from tool input
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.filePath // empty')

if [ -z "$FILE_PATH" ]; then
    exit 0
fi

# Only care about frontend component/style files
# Match .tsx, .css, .scss files — but not test/spec files
if echo "$FILE_PATH" | grep -qE '\.(tsx|css|scss)$'; then
    if ! echo "$FILE_PATH" | grep -qE '(\.spec\.|\.test\.)'; then
        echo "FRONTEND FILE MODIFIED: $(basename "$FILE_PATH") -- consider running a design review before completing this task (design system compliance, dark mode, accessibility, state coverage)."
    fi
fi

exit 0

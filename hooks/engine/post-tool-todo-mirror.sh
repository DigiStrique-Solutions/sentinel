#!/bin/bash
# POST-TOOL HOOK (TodoWrite): Mirror todo state to filesystem
#
# After every TodoWrite call, saves the current todo list to a JSON file
# that the stop-enforcer can read independently. This allows the stop hook
# to verify that all tasks were completed — catching the case where Claude
# claims "all done!" but the todo list shows pending items.
#
# The mirror file is the contract: if todos exist and any are not completed,
# the stop hook will flag it.
#
# State is stored in .sentinel/sessions/<id>/todos.json

set -euo pipefail

INPUT=$(cat)
CWD=$(echo "$INPUT" | jq -r '.cwd // empty')
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty')

# Extract the todo list from tool input
TODOS=$(echo "$INPUT" | jq -r '.tool_input.todos // empty')
if [ -z "$TODOS" ] || [ "$TODOS" = "null" ]; then
    exit 0
fi

# Write todo state to session-scoped file
SENTINEL_DIR="${CWD}/.sentinel"
if [ -n "$SESSION_ID" ]; then
    SHORT_ID="${SESSION_ID:0:12}"
    SENTINEL_DIR="${CWD}/.sentinel/sessions/${SHORT_ID}"
fi
mkdir -p "$SENTINEL_DIR"

TODO_FILE="${SENTINEL_DIR}/todos.json"

# Save the full todo state with timestamp
echo "$INPUT" | jq '{
    timestamp: (now | todate),
    todos: .tool_input.todos
}' > "$TODO_FILE" 2>/dev/null || {
    # Fallback if jq expression fails
    echo "$TODOS" | jq '.' > "$TODO_FILE" 2>/dev/null || echo "$TODOS" > "$TODO_FILE"
}

exit 0

#!/bin/bash
# SHARED FUNCTION: Log events to the team activity feed
#
# Usage: source this file, then call log_activity "event description"
# Appends a timestamped, attributed line to vault/activity/YYYY-MM-DD.md
#
# Requires CWD or REPO_ROOT to be set before sourcing.
# If vault/activity/ doesn't exist, logging is silently skipped (not a team setup).

log_activity() {
    local EVENT_MSG="$1"

    # Determine repo root
    local ROOT="${REPO_ROOT:-${CWD:-$(pwd)}}"

    local ACTIVITY_DIR="${ROOT}/vault/activity"

    # Skip if activity directory doesn't exist (not a team setup or no vault)
    if [ ! -d "$ACTIVITY_DIR" ]; then
        return 0
    fi

    # Get author from git config
    local AUTHOR
    AUTHOR=$(git -C "$ROOT" config user.name 2>/dev/null || echo "unknown")

    # Get current time
    local TIMESTAMP
    TIMESTAMP=$(date +%H:%M)

    local TODAY
    TODAY=$(date +%Y-%m-%d)

    local ACTIVITY_FILE="${ACTIVITY_DIR}/${TODAY}.md"

    # Create file with header if it doesn't exist
    if [ ! -f "$ACTIVITY_FILE" ]; then
        echo "# Activity — ${TODAY}" > "$ACTIVITY_FILE"
        echo "" >> "$ACTIVITY_FILE"
    fi

    # Append the event
    echo "- \`${TIMESTAMP}\` **${AUTHOR}** — ${EVENT_MSG}" >> "$ACTIVITY_FILE"
}

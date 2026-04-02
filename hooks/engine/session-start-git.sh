#!/bin/bash
# SESSION START HOOK: Auto-branch if on main/master
#
# When a session starts, checks if the user is on the main/master branch.
# If so, creates a new feature branch automatically so work is isolated.
# The user never needs to think about branches.
#
# Branch naming: sentinel/<date>-<time> (e.g., sentinel/2026-04-02-1345)
# If the user is already on a non-main branch, does nothing.

set -euo pipefail

INPUT=$(cat)
CWD=$(echo "$INPUT" | jq -r '.cwd // empty')
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty')

[ -z "$CWD" ] && exit 0

# Only act inside git repos
if ! git -C "$CWD" rev-parse --is-inside-work-tree &>/dev/null; then
    exit 0
fi

# Skip if this session is already in a worktree (session-start-isolate handled branching)
REPO_ROOT=$(git -C "$CWD" rev-parse --show-toplevel 2>/dev/null || echo "$CWD")
if [ -n "$SESSION_ID" ]; then
    SHORT_ID="${SESSION_ID:0:12}"
    SESSION_FILE="${REPO_ROOT}/.sentinel/sessions/${SHORT_ID}.json"
    if [ -f "$SESSION_FILE" ]; then
        IS_WORKTREE=$(jq -r '.worktree // false' "$SESSION_FILE" 2>/dev/null || echo "false")
        if [ "$IS_WORKTREE" = "true" ]; then
            WORKTREE_BRANCH=$(jq -r '.worktree_branch // empty' "$SESSION_FILE" 2>/dev/null || echo "")
            echo "GIT AUTOPILOT: Working in isolated worktree on branch '${WORKTREE_BRANCH}'. Commits will happen automatically when you're done."
            exit 0
        fi
    fi
fi

CURRENT_BRANCH=$(git -C "$CWD" branch --show-current 2>/dev/null || echo "")

# If on main, master, or detached HEAD — create a working branch
if [ "$CURRENT_BRANCH" = "main" ] || [ "$CURRENT_BRANCH" = "master" ] || [ -z "$CURRENT_BRANCH" ]; then
    TIMESTAMP=$(date +%Y-%m-%d-%H%M)
    NEW_BRANCH="sentinel/${TIMESTAMP}"

    git -C "$CWD" checkout -b "$NEW_BRANCH" --quiet 2>/dev/null

    echo "GIT AUTOPILOT: Created branch '${NEW_BRANCH}' — your work is isolated from main. Commits will happen automatically when you're done."
else
    echo "GIT AUTOPILOT: Working on branch '${CURRENT_BRANCH}'. Commits will happen automatically when you're done."
fi

exit 0

#!/bin/bash
# PROMPT HOOK: Detect bug-fix tasks and set stricter verification mode
#
# When the user's prompt describes a bug fix (keywords like "fix", "bug",
# "broken", "error", "doesn't work"), or the git branch is fix/* or bugfix/*,
# sets a flag that the stop-enforcer uses to enforce reproduce-first
# verification (RED-GREEN pattern).
#
# This avoids annoying false positives on new feature work, where there is
# no "reproduce" step because the feature doesn't exist yet.
#
# Flag stored in .sentinel/sessions/<id>/mode-bugfix

set -euo pipefail

INPUT=$(cat)
CWD=$(echo "$INPUT" | jq -r '.cwd // empty')
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty')
PROMPT=$(echo "$INPUT" | jq -r '.prompt // empty')

[ -z "$CWD" ] && exit 0
[ -z "$SESSION_ID" ] && exit 0

# Setup sentinel tracking directory
SENTINEL_DIR="${CWD}/.sentinel"
SHORT_ID="${SESSION_ID:0:12}"
SENTINEL_DIR="${CWD}/.sentinel/sessions/${SHORT_ID}"
mkdir -p "$SENTINEL_DIR"

BUGFIX_FLAG="${SENTINEL_DIR}/mode-bugfix"

# Already detected — skip further checks
if [ -f "$BUGFIX_FLAG" ]; then
    exit 0
fi

IS_BUGFIX=false

# Check 1: Prompt keywords
if [ -n "$PROMPT" ]; then
    if echo "$PROMPT" | grep -qiE '(fix |fix$|bug |bug$|broken|doesnt work|does not work|doesn.t work|regression|not working|stopped working|crash|failing|fails)'; then
        IS_BUGFIX=true
    fi
fi

# Check 2: Git branch name
if [ "$IS_BUGFIX" = "false" ] && command -v git &>/dev/null; then
    BRANCH=$(git -C "$CWD" branch --show-current 2>/dev/null || echo "")
    if echo "$BRANCH" | grep -qiE '^(fix|bugfix|hotfix)/'; then
        IS_BUGFIX=true
    fi
fi

# Set the flag if bug-fix mode detected
if [ "$IS_BUGFIX" = "true" ]; then
    touch "$BUGFIX_FLAG"
fi

exit 0

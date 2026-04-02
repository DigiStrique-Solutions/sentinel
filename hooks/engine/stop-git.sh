#!/bin/bash
# STOP HOOK: Auto-commit all changes when session ends
#
# When a session ends, automatically:
# 1. Stages all changed files (excluding sensitive files)
# 2. Generates a commit message from the modified files
# 3. Commits everything
#
# The user never types a commit message or runs git commands.
# Works silently — no commit if there are no changes.

set -euo pipefail

INPUT=$(cat)
CWD=$(echo "$INPUT" | jq -r '.cwd // empty')

[ -z "$CWD" ] && exit 0

# Only act inside git repos
if ! git -C "$CWD" rev-parse --is-inside-work-tree &>/dev/null; then
    exit 0
fi

# Check if there are any changes to commit
if git -C "$CWD" diff --quiet HEAD 2>/dev/null && git -C "$CWD" diff --cached --quiet 2>/dev/null; then
    # Check for untracked files too
    UNTRACKED=$(git -C "$CWD" ls-files --others --exclude-standard 2>/dev/null | head -1)
    if [ -z "$UNTRACKED" ]; then
        exit 0
    fi
fi

# --- Build .gitignore-safe staging ---
# Never commit these patterns
EXCLUDE_PATTERNS=(.env .env.* *.pem *.key credentials.json secrets.* .sentinel/)

cd "$CWD"

# Stage everything except excluded patterns
git add -A 2>/dev/null || true

# Unstage sensitive files
for pattern in "${EXCLUDE_PATTERNS[@]}"; do
    git reset HEAD -- "$pattern" 2>/dev/null || true
done

# Check if anything is actually staged after filtering
if git diff --cached --quiet 2>/dev/null; then
    exit 0
fi

# --- Generate commit message from changes ---
STAGED_FILES=$(git diff --cached --name-only 2>/dev/null)
FILE_COUNT=$(echo "$STAGED_FILES" | wc -l | tr -d ' ')

# Determine the type of changes
HAS_TESTS=$(echo "$STAGED_FILES" | grep -cE '(test_|_test\.|\.test\.|\.spec\.)' 2>/dev/null || echo "0")
HAS_VAULT=$(echo "$STAGED_FILES" | grep -c "^vault/" 2>/dev/null || echo "0")
HAS_NEW=$(git diff --cached --diff-filter=A --name-only 2>/dev/null | wc -l | tr -d ' ')
HAS_DELETED=$(git diff --cached --diff-filter=D --name-only 2>/dev/null | wc -l | tr -d ' ')

# Pick commit type
COMMIT_TYPE="chore"
if [ "$HAS_NEW" -gt 0 ] && [ "$HAS_DELETED" -eq 0 ]; then
    COMMIT_TYPE="feat"
elif [ "$HAS_TESTS" -gt 0 ] && [ "$HAS_TESTS" -ge "$FILE_COUNT" ]; then
    COMMIT_TYPE="test"
elif [ "$HAS_VAULT" -gt 0 ] && [ "$HAS_VAULT" -ge "$FILE_COUNT" ]; then
    COMMIT_TYPE="docs"
fi

# Build a descriptive summary from file paths
# Group by top-level directory
AREAS=$(echo "$STAGED_FILES" | awk -F/ '{print $1}' | sort -u | head -3 | tr '\n' ', ' | sed 's/,$//')

# Get the most common file extension to hint at what changed
EXTENSIONS=$(echo "$STAGED_FILES" | grep -oE '\.[a-z]+$' | sort | uniq -c | sort -rn | head -1 | awk '{print $2}')

COMMIT_MSG="${COMMIT_TYPE}: update ${AREAS}"
if [ "$FILE_COUNT" -gt 1 ]; then
    COMMIT_MSG="${COMMIT_MSG} (${FILE_COUNT} files)"
fi

# Commit
git commit -m "$COMMIT_MSG" --quiet 2>/dev/null

BRANCH=$(git branch --show-current 2>/dev/null || echo "unknown")
SHORT_SHA=$(git rev-parse --short HEAD 2>/dev/null || echo "")

# Log commit to activity feed
PLUGIN_LOGGER="$(dirname "$0")/activity-logger.sh"
if [ -f "$PLUGIN_LOGGER" ]; then
    REPO_ROOT="$CWD" source "$PLUGIN_LOGGER"
    log_activity "Committed ${FILE_COUNT} file(s) to \`${BRANCH}\` [${SHORT_SHA}] — ${COMMIT_MSG}"
fi

echo "GIT AUTOPILOT: Committed ${FILE_COUNT} file(s) to '${BRANCH}' [${SHORT_SHA}] — ${COMMIT_MSG}"

exit 0

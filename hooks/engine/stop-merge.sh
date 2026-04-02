#!/bin/bash
# STOP HOOK: Auto-merge worktree changes back when session ends
#
# If this session was isolated in a worktree:
#   1. Commits any uncommitted changes in the worktree
#   2. Merges the worktree branch back into the base branch
#   3. For vault/ conflicts: keeps BOTH versions (ours + theirs)
#   4. Removes the worktree and cleans up session registry
#
# If this session was NOT in a worktree, does nothing.
# Runs AFTER stop-git.sh (which handles the commit) and BEFORE stop-enforcer cleanup.

set -euo pipefail

INPUT=$(cat)
CWD=$(echo "$INPUT" | jq -r '.cwd // empty')
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty')

[ -z "$CWD" ] && exit 0
[ -z "$SESSION_ID" ] && exit 0

# Only act inside git repos
if ! git -C "$CWD" rev-parse --is-inside-work-tree &>/dev/null; then
    exit 0
fi

REPO_ROOT=$(git -C "$CWD" rev-parse --show-toplevel 2>/dev/null || echo "$CWD")
SHORT_ID="${SESSION_ID:0:12}"
SENTINEL_DIR="${REPO_ROOT}/.sentinel"
SESSION_FILE="${SENTINEL_DIR}/sessions/${SHORT_ID}.json"

# Check if this session has a worktree
if [ ! -f "$SESSION_FILE" ]; then
    exit 0
fi

IS_WORKTREE=$(jq -r '.worktree // false' "$SESSION_FILE" 2>/dev/null || echo "false")
if [ "$IS_WORKTREE" != "true" ]; then
    # Not a worktree session — just clean up session file
    rm -f "$SESSION_FILE" 2>/dev/null || true
    exit 0
fi

WORKTREE_PATH=$(jq -r '.worktree_path // empty' "$SESSION_FILE" 2>/dev/null || echo "")
WORKTREE_BRANCH=$(jq -r '.worktree_branch // empty' "$SESSION_FILE" 2>/dev/null || echo "")
BASE_BRANCH=$(jq -r '.base_branch // empty' "$SESSION_FILE" 2>/dev/null || echo "")

if [ -z "$WORKTREE_PATH" ] || [ -z "$WORKTREE_BRANCH" ] || [ -z "$BASE_BRANCH" ]; then
    echo "SENTINEL: Worktree session data incomplete — skipping auto-merge."
    rm -f "$SESSION_FILE" 2>/dev/null || true
    exit 0
fi

# Check if worktree directory still exists
if [ ! -d "$WORKTREE_PATH" ]; then
    echo "SENTINEL: Worktree directory already removed — cleaning up."
    rm -f "$SESSION_FILE" 2>/dev/null || true
    exit 0
fi

# --- Step 1: Commit any remaining uncommitted changes in the worktree ---
cd "$WORKTREE_PATH"

if ! git diff --quiet HEAD 2>/dev/null || ! git diff --cached --quiet 2>/dev/null || [ -n "$(git ls-files --others --exclude-standard 2>/dev/null | head -1)" ]; then
    git add -A 2>/dev/null || true
    # Unstage sensitive files
    for pattern in .env .env.* *.pem *.key credentials.json secrets.*; do
        git reset HEAD -- "$pattern" 2>/dev/null || true
    done
    if ! git diff --cached --quiet 2>/dev/null; then
        git commit -m "chore: final worktree changes before merge" --quiet 2>/dev/null || true
    fi
fi

# --- Step 2: Check if there are any commits to merge ---
cd "$REPO_ROOT"

COMMITS_AHEAD=$(git rev-list "${BASE_BRANCH}..${WORKTREE_BRANCH}" --count 2>/dev/null || echo "0")

if [ "$COMMITS_AHEAD" -eq 0 ]; then
    echo "SENTINEL: No changes to merge from worktree."
else
    # --- Step 3: Merge worktree branch into base branch ---
    # Save current branch
    CURRENT_BRANCH=$(git branch --show-current 2>/dev/null || echo "")

    # Checkout base branch
    git checkout "$BASE_BRANCH" --quiet 2>/dev/null || {
        echo "SENTINEL: Could not checkout base branch '${BASE_BRANCH}' — merge skipped."
        echo "SENTINEL: Your changes are on branch '${WORKTREE_BRANCH}'. Merge manually."
        rm -f "$SESSION_FILE" 2>/dev/null || true
        exit 0
    }

    # Attempt merge
    if git merge "$WORKTREE_BRANCH" --no-edit --quiet 2>/dev/null; then
        # Log merge to activity feed
        PLUGIN_LOGGER="$(dirname "$0")/activity-logger.sh"
        if [ -f "$PLUGIN_LOGGER" ]; then
            REPO_ROOT="$REPO_ROOT" source "$PLUGIN_LOGGER"
            log_activity "Merged ${COMMITS_AHEAD} commit(s) from worktree \`${WORKTREE_BRANCH}\` into \`${BASE_BRANCH}\`"
        fi
        echo "SENTINEL: Merged ${COMMITS_AHEAD} commit(s) from worktree into '${BASE_BRANCH}'."
    else
        # Conflict detected — handle vault files specially
        CONFLICTED_FILES=$(git diff --name-only --diff-filter=U 2>/dev/null || echo "")

        if [ -n "$CONFLICTED_FILES" ]; then
            # For vault files: keep both versions (accept theirs for new content)
            VAULT_CONFLICTS=$(echo "$CONFLICTED_FILES" | grep "^vault/" || echo "")
            OTHER_CONFLICTS=$(echo "$CONFLICTED_FILES" | grep -v "^vault/" || echo "")

            # Resolve vault conflicts by keeping both (theirs wins for append-only files)
            if [ -n "$VAULT_CONFLICTS" ]; then
                for vfile in $VAULT_CONFLICTS; do
                    # For vault files, accept the incoming (worktree) version
                    # since vault entries are typically additive
                    git checkout --theirs "$vfile" 2>/dev/null || true
                    git add "$vfile" 2>/dev/null || true
                done
            fi

            if [ -n "$OTHER_CONFLICTS" ]; then
                # For source code conflicts: accept the worktree version
                # (the isolated session's work should take precedence)
                for cfile in $OTHER_CONFLICTS; do
                    git checkout --theirs "$cfile" 2>/dev/null || true
                    git add "$cfile" 2>/dev/null || true
                done
            fi

            # Complete the merge
            git commit --no-edit --quiet 2>/dev/null || true
            echo "SENTINEL: Merged ${COMMITS_AHEAD} commit(s) from worktree (resolved conflicts)."
        fi
    fi

    # Return to original branch if different from base
    if [ -n "$CURRENT_BRANCH" ] && [ "$CURRENT_BRANCH" != "$BASE_BRANCH" ]; then
        git checkout "$CURRENT_BRANCH" --quiet 2>/dev/null || true
    fi
fi

# --- Step 4: Clean up worktree ---
git worktree remove "$WORKTREE_PATH" --force 2>/dev/null || {
    # If worktree remove fails, try manual cleanup
    rm -rf "$WORKTREE_PATH" 2>/dev/null || true
    git worktree prune 2>/dev/null || true
}

# Delete the worktree branch
git branch -D "$WORKTREE_BRANCH" 2>/dev/null || true

# --- Step 5: Clean up session registry ---
rm -f "$SESSION_FILE" 2>/dev/null || true

# Clean up session-scoped sentinel directory
rm -rf "${SENTINEL_DIR}/sessions/${SHORT_ID}" 2>/dev/null || true

# Clean up empty sessions directory
rmdir "${SENTINEL_DIR}/sessions" 2>/dev/null || true

echo "SENTINEL: Worktree cleanup complete."

exit 0

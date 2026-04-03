#!/bin/bash
# SESSION START HOOK: Detect concurrent sessions and auto-isolate with worktrees
#
# Reads ~/.claude/sessions/*.json to discover other active Claude Code sessions
# working in the same repo. If a concurrent session is found:
#   1. Creates a git worktree at .claude/worktrees/sentinel-<session-id>/
#   2. Outputs instructions telling Claude to work in the worktree
#   3. Registers this session in .sentinel/sessions/
#
# If this is the only session, registers and continues normally.
#
# The stop-merge.sh hook handles merging worktree changes back when done.

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

# Get the repo root (handles being invoked from subdirectories)
REPO_ROOT=$(git -C "$CWD" rev-parse --show-toplevel 2>/dev/null || echo "$CWD")

# --- Session registry ---
SENTINEL_DIR="${REPO_ROOT}/.sentinel"
SESSIONS_DIR="${SENTINEL_DIR}/sessions"
mkdir -p "$SESSIONS_DIR" 2>/dev/null || true

# Resolve the real Claude Code PID from ~/.claude/sessions/
# Hook $$ is the bash subprocess PID (ephemeral, dies after hook exits).
# The actual Claude Code PID lives in ~/.claude/sessions/{pid}.json
CLAUDE_PID=""
CLAUDE_SESSIONS_DIR="${HOME}/.claude/sessions"
if [ -d "$CLAUDE_SESSIONS_DIR" ]; then
    for pid_file in "${CLAUDE_SESSIONS_DIR}"/*.json; do
        [ -f "$pid_file" ] || continue
        FILE_SID=$(jq -r '.sessionId // empty' "$pid_file" 2>/dev/null || echo "")
        if [ "$FILE_SID" = "$SESSION_ID" ]; then
            CLAUDE_PID=$(jq -r '.pid // empty' "$pid_file" 2>/dev/null || echo "")
            break
        fi
    done
fi
# Fallback: use $PPID if we couldn't find it (better than $$)
CLAUDE_PID="${CLAUDE_PID:-$PPID}"

# Clean up stale session entries (process no longer running)
for session_file in "${SESSIONS_DIR}"/*.json; do
    [ -f "$session_file" ] || continue
    STORED_PID=$(jq -r '.pid // empty' "$session_file" 2>/dev/null || echo "")
    if [ -n "$STORED_PID" ] && ! kill -0 "$STORED_PID" 2>/dev/null; then
        rm -f "$session_file" 2>/dev/null || true
    fi
done

# Check for concurrent sessions in the SAME repo
CONCURRENT_COUNT=0
CONCURRENT_IDS=""

# Check Claude Code's session registry for concurrent sessions
if [ -d "$CLAUDE_SESSIONS_DIR" ]; then
    for pid_file in "${CLAUDE_SESSIONS_DIR}"/*.json; do
        [ -f "$pid_file" ] || continue
        OTHER_PID=$(jq -r '.pid // empty' "$pid_file" 2>/dev/null || echo "")
        OTHER_CWD=$(jq -r '.cwd // empty' "$pid_file" 2>/dev/null || echo "")
        OTHER_ID=$(jq -r '.sessionId // empty' "$pid_file" 2>/dev/null || echo "")

        # Skip self
        [ "$OTHER_ID" = "$SESSION_ID" ] && continue

        # Skip if process is dead
        if [ -n "$OTHER_PID" ] && ! kill -0 "$OTHER_PID" 2>/dev/null; then
            continue
        fi

        # Check if the other session is in the same repo
        if [ -n "$OTHER_CWD" ]; then
            OTHER_REPO_ROOT=$(git -C "$OTHER_CWD" rev-parse --show-toplevel 2>/dev/null || echo "")
            if [ "$OTHER_REPO_ROOT" = "$REPO_ROOT" ]; then
                CONCURRENT_COUNT=$((CONCURRENT_COUNT + 1))
                CONCURRENT_IDS="${CONCURRENT_IDS} ${OTHER_ID}"
            fi
        fi
    done
fi

# Register this session
SHORT_ID="${SESSION_ID:0:12}"
cat > "${SESSIONS_DIR}/${SHORT_ID}.json" << EOF
{
    "session_id": "${SESSION_ID}",
    "pid": ${CLAUDE_PID},
    "cwd": "${CWD}",
    "repo_root": "${REPO_ROOT}",
    "started_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "worktree": false
}
EOF

# --- If concurrent sessions detected, create worktree ---
if [ "$CONCURRENT_COUNT" -gt 0 ]; then
    WORKTREE_NAME="sentinel-${SHORT_ID}"
    WORKTREE_DIR="${REPO_ROOT}/.claude/worktrees/${WORKTREE_NAME}"

    # Get the current branch or default branch
    CURRENT_BRANCH=$(git -C "$REPO_ROOT" branch --show-current 2>/dev/null || echo "")
    BASE_BRANCH="${CURRENT_BRANCH:-HEAD}"

    # Create the worktree
    mkdir -p "$(dirname "$WORKTREE_DIR")" 2>/dev/null || true

    if git -C "$REPO_ROOT" worktree add -B "worktree-${WORKTREE_NAME}" "$WORKTREE_DIR" "$BASE_BRANCH" --quiet 2>/dev/null; then
        # Update session registry with worktree info
        cat > "${SESSIONS_DIR}/${SHORT_ID}.json" << EOF
{
    "session_id": "${SESSION_ID}",
    "pid": ${CLAUDE_PID},
    "cwd": "${CWD}",
    "repo_root": "${REPO_ROOT}",
    "worktree": true,
    "worktree_path": "${WORKTREE_DIR}",
    "worktree_branch": "worktree-${WORKTREE_NAME}",
    "base_branch": "${BASE_BRANCH}",
    "started_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF

        # Symlink node_modules if they exist (avoid disk bloat)
        if [ -d "${REPO_ROOT}/node_modules" ] && [ ! -d "${WORKTREE_DIR}/node_modules" ]; then
            ln -s "${REPO_ROOT}/node_modules" "${WORKTREE_DIR}/node_modules" 2>/dev/null || true
        fi

        # Copy .env files if a .worktreeinclude exists
        if [ -f "${REPO_ROOT}/.worktreeinclude" ]; then
            while IFS= read -r pattern; do
                [ -z "$pattern" ] && continue
                [[ "$pattern" == \#* ]] && continue
                for f in ${REPO_ROOT}/${pattern}; do
                    [ -f "$f" ] || continue
                    REL="${f#${REPO_ROOT}/}"
                    mkdir -p "$(dirname "${WORKTREE_DIR}/${REL}")" 2>/dev/null || true
                    cp "$f" "${WORKTREE_DIR}/${REL}" 2>/dev/null || true
                done
            done < "${REPO_ROOT}/.worktreeinclude"
        fi

        echo "CONCURRENT SESSION DETECTED: ${CONCURRENT_COUNT} other session(s) active in this repo."
        echo "AUTO-ISOLATED: Created worktree at ${WORKTREE_DIR}"
        echo ""
        echo "IMPORTANT — You MUST work in the isolated copy to avoid conflicts:"
        echo "  Working directory: ${WORKTREE_DIR}"
        echo "  Branch: worktree-${WORKTREE_NAME}"
        echo "  All file reads, writes, and edits should use paths under ${WORKTREE_DIR}/"
        echo "  Changes will be auto-merged back when this session ends."
    else
        # Worktree creation failed — warn but don't block
        echo "CONCURRENT SESSION WARNING: ${CONCURRENT_COUNT} other session(s) active in this repo."
        echo "Could not create worktree for isolation. Be careful with file edits — conflicts may occur."
        echo "Consider working on different files than the other session(s)."
    fi
else
    echo "SENTINEL: Session registered. No concurrent sessions detected."
fi

exit 0

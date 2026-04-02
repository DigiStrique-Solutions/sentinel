#!/usr/bin/env bats

load "${BATS_TEST_DIRNAME}/../helpers/common"

HOOK="${SENTINEL_ROOT}/hooks/engine/stop-merge.sh"
SESSION_ID="test-session-1234567890"
SHORT_ID="test-session"

setup() {
    export PROJECT_DIR="${BATS_TEST_TMPDIR}/project"
    mkdir -p "$PROJECT_DIR"
    init_test_git_repo "$PROJECT_DIR"
    mkdir -p "${PROJECT_DIR}/.sentinel/sessions"
}

# --- Graceful exits ---

@test "exits when no session file" {
    run_hook "$HOOK" cwd="$PROJECT_DIR" session_id="$SESSION_ID"
    assert_success
    assert_output ""
}

@test "cleans up non-worktree session file" {
    cat > "${PROJECT_DIR}/.sentinel/sessions/${SHORT_ID}.json" <<EOF
{
    "session_id": "${SESSION_ID}",
    "pid": $$,
    "cwd": "${PROJECT_DIR}",
    "repo_root": "${PROJECT_DIR}",
    "worktree": false
}
EOF
    run_hook "$HOOK" cwd="$PROJECT_DIR" session_id="$SESSION_ID"
    assert_success
    # Non-worktree session file should be cleaned up
    assert_file_not_exist "${PROJECT_DIR}/.sentinel/sessions/${SHORT_ID}.json"
}

@test "reads worktree fields from session JSON" {
    # Create a worktree session file with all required fields
    cat > "${PROJECT_DIR}/.sentinel/sessions/${SHORT_ID}.json" <<EOF
{
    "session_id": "${SESSION_ID}",
    "pid": $$,
    "cwd": "${PROJECT_DIR}",
    "repo_root": "${PROJECT_DIR}",
    "worktree": true,
    "worktree_path": "${PROJECT_DIR}/.claude/worktrees/test",
    "worktree_branch": "worktree-test",
    "base_branch": "main"
}
EOF
    # The worktree path doesn't exist so this will exit early
    run_hook "$HOOK" cwd="$PROJECT_DIR" session_id="$SESSION_ID"
    assert_success
}

@test "exits when worktree path missing" {
    cat > "${PROJECT_DIR}/.sentinel/sessions/${SHORT_ID}.json" <<EOF
{
    "session_id": "${SESSION_ID}",
    "worktree": true,
    "worktree_path": "",
    "worktree_branch": "worktree-test",
    "base_branch": "main"
}
EOF
    run_hook "$HOOK" cwd="$PROJECT_DIR" session_id="$SESSION_ID"
    assert_success
}

# --- Merge with real worktree ---

@test "merges worktree branch into base" {
    cd "$PROJECT_DIR"
    local base_branch
    base_branch=$(git branch --show-current)

    # Create a worktree
    local wt_dir="${PROJECT_DIR}/.claude/worktrees/merge-test"
    mkdir -p "$(dirname "$wt_dir")"
    git worktree add -B "worktree-merge-test" "$wt_dir" "$base_branch" 2>/dev/null

    # Make a change in the worktree
    echo "worktree change" > "${wt_dir}/worktree-file.txt"
    cd "$wt_dir"
    git add worktree-file.txt
    git commit -q -m "worktree commit"
    cd "$PROJECT_DIR"

    # Create session file
    cat > "${PROJECT_DIR}/.sentinel/sessions/${SHORT_ID}.json" <<EOF
{
    "session_id": "${SESSION_ID}",
    "pid": $$,
    "cwd": "${wt_dir}",
    "repo_root": "${PROJECT_DIR}",
    "worktree": true,
    "worktree_path": "${wt_dir}",
    "worktree_branch": "worktree-merge-test",
    "base_branch": "${base_branch}"
}
EOF

    run_hook "$HOOK" cwd="$PROJECT_DIR" session_id="$SESSION_ID"
    assert_success

    # The worktree file should now be in the base branch
    cd "$PROJECT_DIR"
    git checkout "$base_branch" 2>/dev/null
    assert_file_exist "${PROJECT_DIR}/worktree-file.txt"
    cd - > /dev/null
}

@test "cleans up session files after merge" {
    cd "$PROJECT_DIR"
    local base_branch
    base_branch=$(git branch --show-current)
    local wt_dir="${PROJECT_DIR}/.claude/worktrees/cleanup-test"
    mkdir -p "$(dirname "$wt_dir")"
    git worktree add -B "worktree-cleanup-test" "$wt_dir" "$base_branch" 2>/dev/null
    cd "$PROJECT_DIR"

    mkdir -p "${PROJECT_DIR}/.sentinel/sessions/${SHORT_ID}"
    echo "tracking" > "${PROJECT_DIR}/.sentinel/sessions/${SHORT_ID}/modified-files.txt"
    cat > "${PROJECT_DIR}/.sentinel/sessions/${SHORT_ID}.json" <<EOF
{
    "session_id": "${SESSION_ID}",
    "pid": $$,
    "cwd": "${wt_dir}",
    "repo_root": "${PROJECT_DIR}",
    "worktree": true,
    "worktree_path": "${wt_dir}",
    "worktree_branch": "worktree-cleanup-test",
    "base_branch": "${base_branch}"
}
EOF

    run_hook "$HOOK" cwd="$PROJECT_DIR" session_id="$SESSION_ID"
    assert_success
    # Session files should be cleaned up
    assert_file_not_exist "${PROJECT_DIR}/.sentinel/sessions/${SHORT_ID}.json"
}

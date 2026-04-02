#!/usr/bin/env bats

load "${BATS_TEST_DIRNAME}/../helpers/common"

HOOK="${SENTINEL_ROOT}/hooks/engine/session-start-isolate.sh"
SESSION_ID="test-session-1234567890"
SHORT_ID="test-session"

setup() {
    export PROJECT_DIR="${BATS_TEST_TMPDIR}/project"
    mkdir -p "$PROJECT_DIR"
    init_test_git_repo "$PROJECT_DIR"
    mkdir -p "${PROJECT_DIR}/.sentinel/sessions"
}

# --- Graceful exits ---

@test "exits when not in git repo" {
    local non_git="${BATS_TEST_TMPDIR}/non-git"
    mkdir -p "$non_git"
    run_hook "$HOOK" cwd="$non_git" session_id="$SESSION_ID"
    assert_success
}

@test "exits when SESSION_ID empty" {
    run_hook "$HOOK" cwd="$PROJECT_DIR" session_id=""
    assert_success
}

# --- Solo session ---

@test "creates session file for solo session" {
    run_hook "$HOOK" cwd="$PROJECT_DIR" session_id="$SESSION_ID"
    assert_success
    assert_file_exist "${PROJECT_DIR}/.sentinel/sessions/${SHORT_ID}.json"
    # Should be non-worktree
    local worktree
    worktree=$(jq -r '.worktree' "${PROJECT_DIR}/.sentinel/sessions/${SHORT_ID}.json")
    [ "$worktree" = "false" ]
}

@test "session JSON has required fields" {
    run_hook "$HOOK" cwd="$PROJECT_DIR" session_id="$SESSION_ID"
    assert_success
    local json="${PROJECT_DIR}/.sentinel/sessions/${SHORT_ID}.json"
    assert_file_exist "$json"
    # Check required fields exist (worktree may be false which is falsy for jq -e)
    run jq -r '.session_id' "$json"
    assert_success
    refute_output "null"
    run jq -r '.pid' "$json"
    assert_success
    refute_output "null"
    run jq -r '.started_at' "$json"
    assert_success
    refute_output "null"
}

# --- Stale PID cleanup ---

@test "cleans up stale PIDs" {
    # Create a session file with a dead PID
    cat > "${PROJECT_DIR}/.sentinel/sessions/dead-session.json" <<'EOF'
{
    "session_id": "dead-session-full-id",
    "pid": 999999999,
    "cwd": "/tmp",
    "repo_root": "/tmp",
    "worktree": false
}
EOF
    run_hook "$HOOK" cwd="$PROJECT_DIR" session_id="$SESSION_ID"
    assert_success
    # Dead session file should be cleaned up
    assert_file_not_exist "${PROJECT_DIR}/.sentinel/sessions/dead-session.json"
}

# --- Concurrent detection ---

@test "skips self in concurrent detection" {
    # Create our own session file (from a previous run)
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
    # Should not trigger worktree creation for self
    refute_output --partial "CONCURRENT"
}

# --- Worktree fields ---

@test "handles detached HEAD gracefully" {
    cd "$PROJECT_DIR"
    git checkout --detach HEAD 2>/dev/null
    cd - > /dev/null
    run_hook "$HOOK" cwd="$PROJECT_DIR" session_id="$SESSION_ID"
    assert_success
    assert_file_exist "${PROJECT_DIR}/.sentinel/sessions/${SHORT_ID}.json"
}

# --- .worktreeinclude ---

@test "skips worktreeinclude when file missing" {
    # No .worktreeinclude file — should not crash
    run_hook "$HOOK" cwd="$PROJECT_DIR" session_id="$SESSION_ID"
    assert_success
}

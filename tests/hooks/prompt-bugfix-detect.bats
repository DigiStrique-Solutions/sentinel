#!/usr/bin/env bats

load "${BATS_TEST_DIRNAME}/../helpers/common"

HOOK="${SENTINEL_ROOT}/hooks/engine/prompt-bugfix-detect.sh"
SESSION_ID="test-session-1234567890"
SHORT_ID="test-session"

setup() {
    export PROJECT_DIR="${BATS_TEST_TMPDIR}/project"
    mkdir -p "$PROJECT_DIR"
    init_test_git_repo "$PROJECT_DIR"
    mkdir -p "${PROJECT_DIR}/.sentinel/sessions/${SHORT_ID}"
}

bugfix_flag_exists() {
    [ -f "${PROJECT_DIR}/.sentinel/sessions/${SHORT_ID}/mode-bugfix" ]
}

# --- Keyword detection ---

@test "detects 'fix' keyword in prompt" {
    run_hook "$HOOK" cwd="$PROJECT_DIR" session_id="$SESSION_ID" prompt="fix the login bug"
    assert_success
    bugfix_flag_exists
}

@test "detects 'bug' keyword in prompt" {
    run_hook "$HOOK" cwd="$PROJECT_DIR" session_id="$SESSION_ID" prompt="there is a bug in the auth module"
    assert_success
    bugfix_flag_exists
}

@test "detects 'broken' keyword in prompt" {
    run_hook "$HOOK" cwd="$PROJECT_DIR" session_id="$SESSION_ID" prompt="the checkout flow is broken"
    assert_success
    bugfix_flag_exists
}

@test "detects 'doesnt work' in prompt" {
    run_hook "$HOOK" cwd="$PROJECT_DIR" session_id="$SESSION_ID" prompt="the search doesnt work"
    assert_success
    bugfix_flag_exists
}

@test "detects 'not working' in prompt" {
    run_hook "$HOOK" cwd="$PROJECT_DIR" session_id="$SESSION_ID" prompt="the API is not working"
    assert_success
    bugfix_flag_exists
}

@test "detects 'regression' in prompt" {
    run_hook "$HOOK" cwd="$PROJECT_DIR" session_id="$SESSION_ID" prompt="this is a regression from last release"
    assert_success
    bugfix_flag_exists
}

@test "detects 'crash' in prompt" {
    run_hook "$HOOK" cwd="$PROJECT_DIR" session_id="$SESSION_ID" prompt="the app crashes when I click submit"
    assert_success
    bugfix_flag_exists
}

@test "does not detect feature requests" {
    run_hook "$HOOK" cwd="$PROJECT_DIR" session_id="$SESSION_ID" prompt="add a new dashboard page"
    assert_success
    ! bugfix_flag_exists
}

@test "does not detect refactoring" {
    run_hook "$HOOK" cwd="$PROJECT_DIR" session_id="$SESSION_ID" prompt="refactor the auth module to use dependency injection"
    assert_success
    ! bugfix_flag_exists
}

# --- Branch name detection ---

@test "detects fix/ branch prefix" {
    cd "$PROJECT_DIR"
    git checkout -b fix/login-redirect 2>/dev/null
    cd - > /dev/null
    run_hook "$HOOK" cwd="$PROJECT_DIR" session_id="$SESSION_ID" prompt="update the redirect logic"
    assert_success
    bugfix_flag_exists
}

@test "detects bugfix/ branch prefix" {
    cd "$PROJECT_DIR"
    git checkout -b bugfix/auth-error 2>/dev/null
    cd - > /dev/null
    run_hook "$HOOK" cwd="$PROJECT_DIR" session_id="$SESSION_ID" prompt="update auth"
    assert_success
    bugfix_flag_exists
}

@test "detects hotfix/ branch prefix" {
    cd "$PROJECT_DIR"
    git checkout -b hotfix/critical-issue 2>/dev/null
    cd - > /dev/null
    run_hook "$HOOK" cwd="$PROJECT_DIR" session_id="$SESSION_ID" prompt="patch the issue"
    assert_success
    bugfix_flag_exists
}

@test "does not flag feature/ branch" {
    cd "$PROJECT_DIR"
    git checkout -b feature/new-dashboard 2>/dev/null
    cd - > /dev/null
    run_hook "$HOOK" cwd="$PROJECT_DIR" session_id="$SESSION_ID" prompt="build the dashboard"
    assert_success
    ! bugfix_flag_exists
}

# --- Idempotency ---

@test "skips if bugfix flag already set" {
    touch "${PROJECT_DIR}/.sentinel/sessions/${SHORT_ID}/mode-bugfix"
    run_hook "$HOOK" cwd="$PROJECT_DIR" session_id="$SESSION_ID" prompt="add a new feature"
    assert_success
    # Flag should still exist (not removed)
    bugfix_flag_exists
}

# --- Edge cases ---

@test "exits gracefully with empty prompt and no git" {
    local non_git="${BATS_TEST_TMPDIR}/non-git"
    mkdir -p "$non_git/.sentinel/sessions/${SHORT_ID}"
    run_hook "$HOOK" cwd="$non_git" session_id="$SESSION_ID" prompt=""
    assert_success
}

@test "case insensitive detection" {
    run_hook "$HOOK" cwd="$PROJECT_DIR" session_id="$SESSION_ID" prompt="FIX the LOGIN BUG"
    assert_success
    bugfix_flag_exists
}

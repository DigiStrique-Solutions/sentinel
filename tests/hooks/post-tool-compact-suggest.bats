#!/usr/bin/env bats

load "${BATS_TEST_DIRNAME}/../helpers/common"

HOOK="${SENTINEL_ROOT}/hooks/engine/post-tool-compact-suggest.sh"
SESSION_ID="test-session-1234567890"
SHORT_ID="test-session"

setup() {
    export PROJECT_DIR="${BATS_TEST_TMPDIR}/project"
    mkdir -p "$PROJECT_DIR"
    mkdir -p "${PROJECT_DIR}/.sentinel/sessions/${SHORT_ID}"
}

# Helper: simulate N tool calls
simulate_calls() {
    local count="$1"
    echo "$count" > "${PROJECT_DIR}/.sentinel/sessions/${SHORT_ID}/tool-call-count"
}

# --- Counter ---

@test "increments tool call counter" {
    run_hook "$HOOK" cwd="$PROJECT_DIR" session_id="$SESSION_ID" command="ls"
    assert_success
    local count
    count=$(cat "${PROJECT_DIR}/.sentinel/sessions/${SHORT_ID}/tool-call-count")
    [ "$count" -eq 1 ]
}

@test "counter increments across calls" {
    simulate_calls 5
    run_hook "$HOOK" cwd="$PROJECT_DIR" session_id="$SESSION_ID" command="ls"
    assert_success
    local count
    count=$(cat "${PROJECT_DIR}/.sentinel/sessions/${SHORT_ID}/tool-call-count")
    [ "$count" -eq 6 ]
}

# --- Threshold suggestion ---

@test "suggests compact at default threshold of 80" {
    simulate_calls 79
    run_hook "$HOOK" cwd="$PROJECT_DIR" session_id="$SESSION_ID" command="ls"
    assert_success
    assert_output --partial "CONTEXT PRESSURE"
    assert_output --partial "/compact"
}

@test "no suggestion before threshold" {
    simulate_calls 50
    run_hook "$HOOK" cwd="$PROJECT_DIR" session_id="$SESSION_ID" command="ls"
    assert_success
    assert_output ""
}

@test "no suggestion after threshold (only once)" {
    simulate_calls 79
    run_hook "$HOOK" cwd="$PROJECT_DIR" session_id="$SESSION_ID" command="ls"
    assert_output --partial "CONTEXT PRESSURE"
    # Second call should not nag
    run_hook "$HOOK" cwd="$PROJECT_DIR" session_id="$SESSION_ID" command="ls"
    assert_success
    assert_output ""
}

# --- Custom threshold ---

@test "respects custom threshold from config" {
    mkdir -p "${PROJECT_DIR}/.sentinel"
    echo '{"compact_suggest_threshold": 30}' > "${PROJECT_DIR}/.sentinel/config.json"
    simulate_calls 29
    run_hook "$HOOK" cwd="$PROJECT_DIR" session_id="$SESSION_ID" command="ls"
    assert_success
    assert_output --partial "CONTEXT PRESSURE"
}

# --- Edge cases ---

@test "exits gracefully with empty session_id" {
    run_hook "$HOOK" cwd="$PROJECT_DIR" session_id="" command="ls"
    assert_success
    assert_output ""
}

@test "exits gracefully with empty cwd" {
    run_hook "$HOOK" cwd="" session_id="$SESSION_ID" command="ls"
    assert_success
    assert_output ""
}

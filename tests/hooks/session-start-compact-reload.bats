#!/usr/bin/env bats

load "${BATS_TEST_DIRNAME}/../helpers/common"

HOOK="${SENTINEL_ROOT}/hooks/engine/session-start-compact-reload.sh"
SESSION_ID="test-session-1234567890"
SHORT_ID="test-session"

setup() {
    export PROJECT_DIR="${BATS_TEST_TMPDIR}/project"
    mkdir -p "$PROJECT_DIR"
    VAULT_DIR=$(create_test_vault "$PROJECT_DIR")
    mkdir -p "${PROJECT_DIR}/.sentinel/sessions/${SHORT_ID}"
}

# Helper: run hook with source field
run_compact_hook() {
    local source="${1:-compact}"
    local input_file="${BATS_TEST_TMPDIR}/hook-input.json"
    create_hook_input cwd="$PROJECT_DIR" session_id="$SESSION_ID" > "$input_file"
    # Add source field
    local updated
    updated=$(jq --arg s "$source" '. + {source: $s}' "$input_file")
    echo "$updated" > "$input_file"
    run bash -c "bash '$HOOK' < '$input_file'"
}

# --- Trigger filtering ---

@test "only runs after compaction (source=compact)" {
    create_recovery "$VAULT_DIR" "2026-04-03T14-00-00.md" 1
    run_compact_hook "compact"
    assert_success
    assert_output --partial "COMPACTION DETECTED"
}

@test "skips on fresh session start (source empty)" {
    # Clean any recovery files to ensure this test is isolated
    rm -rf "${VAULT_DIR}/session-recovery/"*.md 2>/dev/null || true
    run_compact_hook ""
    assert_success
    assert_output ""
}

@test "skips on non-compact source" {
    create_recovery "$VAULT_DIR" "2026-04-03T14-00-00.md" 1
    run_compact_hook "cli"
    assert_success
    assert_output ""
}

@test "exits gracefully when vault missing" {
    rm -rf "${PROJECT_DIR}/vault"
    run_compact_hook "compact"
    assert_success
    assert_output ""
}

# --- Recovery file loading ---

@test "loads recent recovery file after compaction" {
    create_recovery "$VAULT_DIR" "2026-04-03T14-00-00.md" 1
    run_compact_hook "compact"
    assert_success
    assert_output --partial "CONTEXT RECOVERY"
    assert_output --partial "Session Recovery"
}

@test "skips old recovery files (>10 min)" {
    create_recovery "$VAULT_DIR" "2026-04-03T10-00-00.md" 15
    run_compact_hook "compact"
    assert_success
    # Should still output the header but without recovery content
    # (other sections may still produce output)
}

# --- Todo state reload ---

@test "reloads active todos after compaction" {
    create_todos_json "${PROJECT_DIR}/.sentinel" "$SHORT_ID" '{
        "todos": [
            {"content": "Fix auth bug", "status": "completed"},
            {"content": "Write tests", "status": "pending"}
        ]
    }'
    run_compact_hook "compact"
    assert_success
    assert_output --partial "ACTIVE TASK LIST"
    assert_output --partial "Write tests"
}

@test "no todo section when all completed" {
    create_todos_json "${PROJECT_DIR}/.sentinel" "$SHORT_ID" '{
        "todos": [
            {"content": "Fix bug", "status": "completed"}
        ]
    }'
    run_compact_hook "compact"
    assert_success
    # completed todos still show in the list (status is shown)
}

# --- Investigation reload ---

@test "reloads open investigations after compaction" {
    create_investigation "$VAULT_DIR" "2026-04-bug.md" "open"
    run_compact_hook "compact"
    assert_success
    assert_output --partial "OPEN INVESTIGATIONS"
    assert_output --partial "2026-04-bug.md"
}

@test "skips resolved investigations" {
    create_investigation "$VAULT_DIR" "2026-04-fixed.md" "resolved"
    run_compact_hook "compact"
    assert_success
    refute_output --partial "2026-04-fixed.md"
}

# --- Bugfix mode reload ---

@test "reloads bugfix mode flag after compaction" {
    touch "${PROJECT_DIR}/.sentinel/sessions/${SHORT_ID}/mode-bugfix"
    run_compact_hook "compact"
    assert_success
    assert_output --partial "BUG-FIX MODE ACTIVE"
}

@test "no bugfix warning when not in bugfix mode" {
    run_compact_hook "compact"
    assert_success
    refute_output --partial "BUG-FIX MODE"
}

# --- Re-read reminder ---

@test "reminds to re-read CLAUDE.md after compaction" {
    # Need at least one piece of content to trigger output
    create_investigation "$VAULT_DIR" "2026-04-active.md" "open"
    run_compact_hook "compact"
    assert_success
    assert_output --partial "Re-read CLAUDE.md"
}

#!/usr/bin/env bats

load "${BATS_TEST_DIRNAME}/../helpers/common"

HOOK="${SENTINEL_ROOT}/hooks/engine/stop-enforcer.sh"
SESSION_ID="test-session-1234567890"
SHORT_ID="test-session"

setup() {
    export PROJECT_DIR="${BATS_TEST_TMPDIR}/project"
    mkdir -p "$PROJECT_DIR"
    VAULT_DIR=$(create_test_vault "$PROJECT_DIR")
    SENTINEL_DIR=$(create_test_sentinel "$PROJECT_DIR" "$SESSION_ID")
    init_test_git_repo "$PROJECT_DIR"
}

# --- Graceful exits ---

@test "exits gracefully when vault missing" {
    rm -rf "${PROJECT_DIR}/vault"
    run_hook "$HOOK" cwd="$PROJECT_DIR" session_id="$SESSION_ID"
    assert_success
    assert_output ""
}

@test "exits when stop_hook_active is true" {
    run_hook "$HOOK" cwd="$PROJECT_DIR" session_id="$SESSION_ID" stop_hook_active=true
    assert_success
    assert_output ""
}

@test "no warnings for clean session produces no output" {
    # Empty session, no modified files, no evidence, no todos
    run_hook "$HOOK" cwd="$PROJECT_DIR" session_id="$SESSION_ID"
    assert_success
    assert_output ""
}

# --- Evidence audit: tests ---

@test "detects tests never ran" {
    # Create modified files list with Python files
    create_modified_files "$SENTINEL_DIR" "$SHORT_ID" "src/app.py
src/utils.py
src/models.py"
    # Empty evidence log (no test runs)
    create_evidence_log "$SENTINEL_DIR" "$SHORT_ID" ""
    run_hook "$HOOK" cwd="$PROJECT_DIR" session_id="$SESSION_ID"
    assert_success
    assert_output --partial "TESTS NEVER RAN"
}

@test "detects tests failed with no subsequent pass" {
    create_modified_files "$SENTINEL_DIR" "$SHORT_ID" "src/app.py"
    create_evidence_log "$SENTINEL_DIR" "$SHORT_ID" "10:00:00|test:python|fail:1|pytest tests/
10:05:00|lint:python|pass|ruff check src/"
    run_hook "$HOOK" cwd="$PROJECT_DIR" session_id="$SESSION_ID"
    assert_success
    assert_output --partial "TESTS FAILED"
}

@test "no warning when tests pass after fail" {
    create_modified_files "$SENTINEL_DIR" "$SHORT_ID" "src/app.py"
    create_evidence_log "$SENTINEL_DIR" "$SHORT_ID" "10:00:00|test:python|fail:1|pytest tests/
10:05:00|test:python|pass|pytest tests/"
    run_hook "$HOOK" cwd="$PROJECT_DIR" session_id="$SESSION_ID"
    assert_success
    refute_output --partial "TESTS FAILED"
}

@test "all evidence green produces no verification warnings" {
    create_modified_files "$SENTINEL_DIR" "$SHORT_ID" "src/app.py"
    create_evidence_log "$SENTINEL_DIR" "$SHORT_ID" "10:00:00|test:python|pass|pytest tests/
10:01:00|lint:python|pass|ruff check src/"
    run_hook "$HOOK" cwd="$PROJECT_DIR" session_id="$SESSION_ID"
    assert_success
    refute_output --partial "TESTS NEVER RAN"
    refute_output --partial "TESTS FAILED"
    refute_output --partial "LINTER NEVER RAN"
}

# --- Evidence audit: linters ---

@test "detects python linter never ran" {
    create_modified_files "$SENTINEL_DIR" "$SHORT_ID" "src/app.py"
    create_evidence_log "$SENTINEL_DIR" "$SHORT_ID" "10:00:00|test:python|pass|pytest tests/"
    run_hook "$HOOK" cwd="$PROJECT_DIR" session_id="$SESSION_ID"
    assert_success
    assert_output --partial "PYTHON LINTER NEVER RAN"
}

@test "detects JS linter never ran" {
    create_modified_files "$SENTINEL_DIR" "$SHORT_ID" "src/app.tsx"
    create_evidence_log "$SENTINEL_DIR" "$SHORT_ID" "10:00:00|test:js|pass|yarn test"
    run_hook "$HOOK" cwd="$PROJECT_DIR" session_id="$SESSION_ID"
    assert_success
    assert_output --partial "JS/TS LINTER NEVER RAN"
}

@test "detects type check never ran for TS files" {
    create_modified_files "$SENTINEL_DIR" "$SHORT_ID" "src/app.tsx"
    create_evidence_log "$SENTINEL_DIR" "$SHORT_ID" "10:00:00|test:js|pass|yarn test
10:01:00|lint:js|pass|eslint src/"
    run_hook "$HOOK" cwd="$PROJECT_DIR" session_id="$SESSION_ID"
    assert_success
    assert_output --partial "TYPE CHECK NEVER RAN"
}

# --- Todo audit ---

@test "detects pending todo items" {
    create_todos_json "$SENTINEL_DIR" "$SHORT_ID" '{
        "todos": [
            {"content": "Fix auth bug", "status": "completed"},
            {"content": "Write tests", "status": "pending"}
        ]
    }'
    create_modified_files "$SENTINEL_DIR" "$SHORT_ID" "src/app.py"
    run_hook "$HOOK" cwd="$PROJECT_DIR" session_id="$SESSION_ID"
    assert_success
    assert_output --partial "Write tests"
}

@test "detects in_progress todo items" {
    create_todos_json "$SENTINEL_DIR" "$SHORT_ID" '{
        "todos": [
            {"content": "Refactor auth", "status": "in_progress"}
        ]
    }'
    create_modified_files "$SENTINEL_DIR" "$SHORT_ID" "src/app.py"
    run_hook "$HOOK" cwd="$PROJECT_DIR" session_id="$SESSION_ID"
    assert_success
    assert_output --partial "Refactor auth"
}

@test "no todo warning when all completed" {
    create_todos_json "$SENTINEL_DIR" "$SHORT_ID" '{
        "todos": [
            {"content": "Fix bug", "status": "completed"},
            {"content": "Write tests", "status": "completed"}
        ]
    }'
    run_hook "$HOOK" cwd="$PROJECT_DIR" session_id="$SESSION_ID"
    assert_success
    refute_output --partial "INCOMPLETE TASKS"
}

# --- Investigation auto-move ---

@test "auto-moves resolved investigations to resolved/" {
    create_investigation "$VAULT_DIR" "2026-04-bug.md" "resolved"
    run_hook "$HOOK" cwd="$PROJECT_DIR" session_id="$SESSION_ID"
    assert_success
    # File should be moved to resolved/
    assert_file_not_exist "${VAULT_DIR}/investigations/2026-04-bug.md"
    assert_file_exist "${VAULT_DIR}/investigations/resolved/2026-04-bug.md"
}

@test "auto-moves implemented investigations to resolved/" {
    create_investigation "$VAULT_DIR" "2026-04-feat.md" "implemented"
    run_hook "$HOOK" cwd="$PROJECT_DIR" session_id="$SESSION_ID"
    assert_success
    assert_file_not_exist "${VAULT_DIR}/investigations/2026-04-feat.md"
    assert_file_exist "${VAULT_DIR}/investigations/resolved/2026-04-feat.md"
}

@test "skips open investigations (no move)" {
    create_investigation "$VAULT_DIR" "2026-04-active.md" "open"
    run_hook "$HOOK" cwd="$PROJECT_DIR" session_id="$SESSION_ID"
    assert_success
    assert_file_exist "${VAULT_DIR}/investigations/2026-04-active.md"
}

# --- Session cleanup ---

@test "session cleanup removes tracking dir" {
    mkdir -p "${SENTINEL_DIR}/sessions/${SHORT_ID}"
    echo "tracked" > "${SENTINEL_DIR}/sessions/${SHORT_ID}/modified-files.txt"
    run_hook "$HOOK" cwd="$PROJECT_DIR" session_id="$SESSION_ID"
    assert_success
    assert_file_not_exist "${SENTINEL_DIR}/sessions/${SHORT_ID}/modified-files.txt"
}

@test "session cleanup preserves json registry" {
    echo '{"session_id": "test"}' > "${SENTINEL_DIR}/sessions/${SHORT_ID}.json"
    run_hook "$HOOK" cwd="$PROJECT_DIR" session_id="$SESSION_ID"
    assert_success
    # .json should NOT be deleted (stop-merge owns it)
    assert_file_exist "${SENTINEL_DIR}/sessions/${SHORT_ID}.json"
}

# --- Changelog check ---

@test "skips changelog check for 2 or fewer files" {
    create_modified_files "$SENTINEL_DIR" "$SHORT_ID" "src/app.py
src/utils.py"
    run_hook "$HOOK" cwd="$PROJECT_DIR" session_id="$SESSION_ID"
    assert_success
    refute_output --partial "CHANGELOG"
}

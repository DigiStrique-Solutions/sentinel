#!/usr/bin/env bats

load "${BATS_TEST_DIRNAME}/../helpers/common"

HOOK="${SENTINEL_ROOT}/hooks/optional/stop-pattern-extractor.sh"
SESSION_ID="test-session-1234567890"
SHORT_ID="test-session"

setup() {
    export PROJECT_DIR="${BATS_TEST_TMPDIR}/project"
    mkdir -p "$PROJECT_DIR"
    VAULT_DIR=$(create_test_vault "$PROJECT_DIR")
    SENTINEL_DIR=$(create_test_sentinel "$PROJECT_DIR" "$SESSION_ID")
    init_test_git_repo "$PROJECT_DIR"

    # 3+ modified files so the file-count threshold passes
    create_modified_files "$SENTINEL_DIR" "$SHORT_ID" "src/a.py
src/b.py
src/c.py"

    # Minimal transcript so the transcript-path check passes
    export FAKE_TRANSCRIPT="${BATS_TEST_TMPDIR}/transcript.jsonl"
    cat > "$FAKE_TRANSCRIPT" <<'EOF'
{"type":"user","message":{"role":"user","content":"hi"}}
EOF
}

write_config() {
    local pattern="$1"
    local background="$2"
    mkdir -p "${PROJECT_DIR}/.sentinel"
    cat > "${PROJECT_DIR}/.sentinel/config.json" <<EOF
{"hooks": {"pattern_extraction": ${pattern}, "background_extraction": ${background}}}
EOF
}

@test "exits gracefully when vault missing" {
    rm -rf "${PROJECT_DIR}/vault"
    run_hook "$HOOK" cwd="$PROJECT_DIR" session_id="$SESSION_ID" transcript_path="$FAKE_TRANSCRIPT"
    assert_success
    assert_output ""
}

@test "exits when stop_hook_active is true" {
    write_config true true
    ANTHROPIC_API_KEY=fake run_hook "$HOOK" cwd="$PROJECT_DIR" session_id="$SESSION_ID" stop_hook_active=true transcript_path="$FAKE_TRANSCRIPT"
    assert_success
    assert_output ""
}

@test "no-op when both flags false" {
    write_config false false
    run_hook "$HOOK" cwd="$PROJECT_DIR" session_id="$SESSION_ID" transcript_path="$FAKE_TRANSCRIPT"
    assert_success
    assert_output ""
    [ ! -f "${PROJECT_DIR}/.sentinel/extraction.log" ]
}

@test "no-op when pattern_extraction true but background_extraction false" {
    write_config true false
    run_hook "$HOOK" cwd="$PROJECT_DIR" session_id="$SESSION_ID" transcript_path="$FAKE_TRANSCRIPT"
    assert_success
    [ ! -f "${PROJECT_DIR}/.sentinel/extraction.log" ]
}

@test "no-op when both flags true but no API key" {
    write_config true true
    # Save and unset for the duration of this test only
    local saved_key="${ANTHROPIC_API_KEY:-}"
    unset ANTHROPIC_API_KEY
    run_hook "$HOOK" cwd="$PROJECT_DIR" session_id="$SESSION_ID" transcript_path="$FAKE_TRANSCRIPT"
    [ -n "$saved_key" ] && export ANTHROPIC_API_KEY="$saved_key"
    assert_success
    [ ! -f "${PROJECT_DIR}/.sentinel/extraction.log" ]
}

@test "no-op when fewer than 3 files modified" {
    write_config true true
    rm -f "${SENTINEL_DIR}/sessions/${SHORT_ID}/modified-files.txt"
    create_modified_files "$SENTINEL_DIR" "$SHORT_ID" "src/only.py"
    ANTHROPIC_API_KEY=fake run_hook "$HOOK" cwd="$PROJECT_DIR" session_id="$SESSION_ID" transcript_path="$FAKE_TRANSCRIPT"
    assert_success
    [ ! -f "${PROJECT_DIR}/.sentinel/extraction.log" ]
}

@test "no-op when transcript path is missing" {
    write_config true true
    ANTHROPIC_API_KEY=fake run_hook "$HOOK" cwd="$PROJECT_DIR" session_id="$SESSION_ID" transcript_path=""
    assert_success
    [ ! -f "${PROJECT_DIR}/.sentinel/extraction.log" ]
}

#!/usr/bin/env bats

load "${BATS_TEST_DIRNAME}/../helpers/common"

HOOK="${SENTINEL_ROOT}/hooks/engine/post-tool-evidence.sh"
SESSION_ID="test-session-1234567890"
SHORT_ID="test-session"

setup() {
    export PROJECT_DIR="${BATS_TEST_TMPDIR}/project"
    mkdir -p "$PROJECT_DIR"
    create_test_sentinel "$PROJECT_DIR" "$SESSION_ID"
}

# Helper: run evidence hook with a specific command and exit code
run_evidence() {
    local cmd="$1"
    local exit_code="${2:-0}"
    local stdout="${3:-}"
    run_hook "$HOOK" \
        cwd="$PROJECT_DIR" \
        session_id="$SESSION_ID" \
        command="$cmd" \
        exit_code="$exit_code" \
        stdout="$stdout"
}

get_evidence() {
    cat "${PROJECT_DIR}/.sentinel/sessions/${SHORT_ID}/evidence.log" 2>/dev/null || echo ""
}

# --- Command detection ---

@test "detects pytest → test:python" {
    run_evidence "pytest tests/ -x -v" "0"
    assert_success
    local evidence
    evidence=$(get_evidence)
    [[ "$evidence" == *"|test:python|"* ]]
}

@test "detects yarn test → test:js" {
    run_evidence "yarn test" "0"
    assert_success
    local evidence
    evidence=$(get_evidence)
    [[ "$evidence" == *"|test:js|"* ]]
}

@test "detects vitest → test:js" {
    run_evidence "vitest run" "0"
    assert_success
    local evidence
    evidence=$(get_evidence)
    [[ "$evidence" == *"|test:js|"* ]]
}

@test "detects playwright test → test:e2e" {
    run_evidence "playwright test" "0"
    assert_success
    local evidence
    evidence=$(get_evidence)
    [[ "$evidence" == *"|test:e2e|"* ]]
}

@test "detects go test → test:other" {
    run_evidence "go test ./..." "0"
    assert_success
    local evidence
    evidence=$(get_evidence)
    [[ "$evidence" == *"|test:other|"* ]]
}

@test "detects cargo test → test:other" {
    run_evidence "cargo test" "0"
    assert_success
    local evidence
    evidence=$(get_evidence)
    [[ "$evidence" == *"|test:other|"* ]]
}

@test "detects ruff check → lint:python" {
    run_evidence "ruff check src/" "0"
    assert_success
    local evidence
    evidence=$(get_evidence)
    [[ "$evidence" == *"|lint:python|"* ]]
}

@test "detects eslint → lint:js" {
    run_evidence "eslint src/" "0"
    assert_success
    local evidence
    evidence=$(get_evidence)
    [[ "$evidence" == *"|lint:js|"* ]]
}

@test "detects tsc --noEmit → typecheck" {
    run_evidence "tsc --noEmit" "0"
    assert_success
    local evidence
    evidence=$(get_evidence)
    [[ "$evidence" == *"|typecheck|"* ]]
}

@test "detects yarn build → build" {
    run_evidence "yarn build" "0"
    assert_success
    local evidence
    evidence=$(get_evidence)
    [[ "$evidence" == *"|build|"* ]]
}

@test "ignores non-verification commands" {
    run_evidence "git status" "0"
    assert_success
    local evidence
    evidence=$(get_evidence)
    [ -z "$evidence" ]
}

@test "ignores ls command" {
    run_evidence "ls -la" "0"
    assert_success
    local evidence
    evidence=$(get_evidence)
    [ -z "$evidence" ]
}

# --- Status detection ---

@test "exit code 0 → pass" {
    run_evidence "pytest tests/" "0"
    assert_success
    local evidence
    evidence=$(get_evidence)
    [[ "$evidence" == *"|pass|"* ]]
}

@test "exit code non-zero → fail:N" {
    run_evidence "pytest tests/" "1"
    assert_success
    local evidence
    evidence=$(get_evidence)
    [[ "$evidence" == *"|fail:1|"* ]]
}

@test "output pattern FAILED → fail (no exit code)" {
    run_hook "$HOOK" \
        cwd="$PROJECT_DIR" \
        session_id="$SESSION_ID" \
        command="pytest tests/" \
        stdout="FAILED 3 tests"
    assert_success
    local evidence
    evidence=$(get_evidence)
    [[ "$evidence" == *"|fail|"* ]]
}

@test "output pattern passed → pass (no exit code)" {
    run_hook "$HOOK" \
        cwd="$PROJECT_DIR" \
        session_id="$SESSION_ID" \
        command="pytest tests/" \
        stdout="5 passed in 2.3s"
    assert_success
    local evidence
    evidence=$(get_evidence)
    [[ "$evidence" == *"|pass|"* ]]
}

@test "output '0 errors' is pass not fail" {
    run_hook "$HOOK" \
        cwd="$PROJECT_DIR" \
        session_id="$SESSION_ID" \
        command="ruff check src/" \
        stdout="All checks passed! 0 errors found."
    assert_success
    local evidence
    evidence=$(get_evidence)
    [[ "$evidence" == *"|pass|"* ]]
}

@test "output '3 errors' is fail" {
    run_hook "$HOOK" \
        cwd="$PROJECT_DIR" \
        session_id="$SESSION_ID" \
        command="ruff check src/" \
        stdout="Found 3 errors."
    assert_success
    local evidence
    evidence=$(get_evidence)
    [[ "$evidence" == *"|fail|"* ]]
}

# --- Log format ---

@test "log line format is TIMESTAMP|CATEGORY|STATUS|COMMAND" {
    run_evidence "pytest tests/" "0"
    assert_success
    local evidence
    evidence=$(get_evidence)
    # Should match HH:MM:SS|category|status|command
    [[ "$evidence" =~ ^[0-9]{2}:[0-9]{2}:[0-9]{2}\| ]]
}

@test "appends to existing evidence log" {
    run_evidence "pytest tests/" "0"
    run_evidence "ruff check src/" "0"
    assert_success
    local line_count
    line_count=$(wc -l < "${PROJECT_DIR}/.sentinel/sessions/${SHORT_ID}/evidence.log" | tr -d ' ')
    [ "$line_count" -eq 2 ]
}

@test "creates session directory if missing" {
    rm -rf "${PROJECT_DIR}/.sentinel/sessions/${SHORT_ID}"
    run_evidence "pytest tests/" "0"
    assert_success
    assert_file_exist "${PROJECT_DIR}/.sentinel/sessions/${SHORT_ID}/evidence.log"
}

@test "exits gracefully for empty command" {
    run_hook "$HOOK" \
        cwd="$PROJECT_DIR" \
        session_id="$SESSION_ID" \
        command=""
    assert_success
}

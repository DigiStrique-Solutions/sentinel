#!/usr/bin/env bats

load "${BATS_TEST_DIRNAME}/../helpers/common"

HOOK="${SENTINEL_ROOT}/hooks/optional/stop-codemap-refresh.sh"
HELPERS="${SENTINEL_ROOT}/scripts/codemap-helpers.sh"
SESSION_ID="codemap-test-session-9876"
SHORT_ID="codemap-test"

setup() {
    export PROJECT_DIR="${BATS_TEST_TMPDIR}/project"
    mkdir -p "$PROJECT_DIR"/{src,.sentinel/sessions/${SHORT_ID},vault/codemap/results}
    cd "$PROJECT_DIR"

    echo 'def f(): pass' > src/a.py
    echo 'def g(): pass' > src/b.py
    echo 'old a' > vault/codemap/results/src--a.py.md
    echo 'old b' > vault/codemap/results/src--b.py.md

    CODEMAP_PROJECT_ROOT="$PROJECT_DIR" bash "$HELPERS" register \
        "${PROJECT_DIR}/vault/codemap" "task" "src/**/*.py" "claude-haiku-4-5" >/dev/null
}

teardown() { cd /; }

write_config() {
    local val="$1"
    echo "{\"hooks\": {\"codemap_refresh\": $val}}" > "${PROJECT_DIR}/.sentinel/config.json"
}

@test "exits gracefully when vault missing" {
    rm -rf "${PROJECT_DIR}/vault"
    run_hook "$HOOK" cwd="$PROJECT_DIR" session_id="$SESSION_ID"
    assert_success
    assert_output ""
}

@test "no-op when stop_hook_active is true" {
    write_config true
    echo "src/a.py" > .sentinel/sessions/${SHORT_ID}/modified-files.txt
    ANTHROPIC_API_KEY=fake run_hook "$HOOK" cwd="$PROJECT_DIR" session_id="$SESSION_ID" stop_hook_active=true
    assert_success
    assert_output ""
}

@test "no-op when codemap_refresh flag is false" {
    write_config false
    sleep 1; echo 'def f(): return 1' > src/a.py
    echo "src/a.py" > .sentinel/sessions/${SHORT_ID}/modified-files.txt
    ANTHROPIC_API_KEY=fake run_hook "$HOOK" cwd="$PROJECT_DIR" session_id="$SESSION_ID"
    assert_success
    assert_output ""
}

@test "no-op when API key is missing" {
    write_config true
    sleep 1; echo 'def f(): return 1' > src/a.py
    echo "src/a.py" > .sentinel/sessions/${SHORT_ID}/modified-files.txt
    local saved="${ANTHROPIC_API_KEY:-}"
    unset ANTHROPIC_API_KEY
    run_hook "$HOOK" cwd="$PROJECT_DIR" session_id="$SESSION_ID"
    [ -n "$saved" ] && export ANTHROPIC_API_KEY="$saved"
    assert_success
    assert_output ""
}

@test "no-op when modified-files.txt is missing" {
    write_config true
    ANTHROPIC_API_KEY=fake run_hook "$HOOK" cwd="$PROJECT_DIR" session_id="$SESSION_ID"
    assert_success
    assert_output ""
}

@test "no-op when modified files do not match any manifest entries" {
    write_config true
    echo "src/unrelated.py" > .sentinel/sessions/${SHORT_ID}/modified-files.txt
    ANTHROPIC_API_KEY=fake run_hook "$HOOK" cwd="$PROJECT_DIR" session_id="$SESSION_ID"
    assert_success
    # Hook returns silently — actual no-op is checked by absence of audit log
    [ ! -f "${PROJECT_DIR}/.sentinel/codemap-refresh.jsonl" ]
}

@test "spawns worker when modified file matches a manifest entry" {
    write_config true
    sleep 1; echo 'def f(): return 1' > src/a.py
    echo "src/a.py" > .sentinel/sessions/${SHORT_ID}/modified-files.txt
    ANTHROPIC_API_KEY=fake run_hook "$HOOK" cwd="$PROJECT_DIR" session_id="$SESSION_ID"
    assert_success
    # Worker runs in background — give it a moment to land an audit record
    local deadline=$((SECONDS + 5))
    while [ ! -f "${PROJECT_DIR}/.sentinel/codemap-refresh.jsonl" ] && [ $SECONDS -lt $deadline ]; do
        sleep 0.2
    done
    [ -f "${PROJECT_DIR}/.sentinel/codemap-refresh.jsonl" ]
}

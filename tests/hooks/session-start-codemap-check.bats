#!/usr/bin/env bats

load "${BATS_TEST_DIRNAME}/../helpers/common"

HOOK="${SENTINEL_ROOT}/hooks/optional/session-start-codemap-check.sh"
HELPERS="${SENTINEL_ROOT}/scripts/codemap-helpers.sh"

setup() {
    export PROJECT_DIR="${BATS_TEST_TMPDIR}/project"
    mkdir -p "$PROJECT_DIR"/{src,.sentinel,vault/codemap/results}
    cd "$PROJECT_DIR"
    echo 'def f(): pass' > src/a.py
    echo 'old a' > vault/codemap/results/src--a.py.md
    # Register so a manifest exists
    CODEMAP_PROJECT_ROOT="$PROJECT_DIR" bash "$HELPERS" register \
        "${PROJECT_DIR}/vault/codemap" "task" "src/**/*.py" "claude-haiku-4-5" >/dev/null
}

teardown() {
    cd /
}

write_config() {
    local val="$1"
    echo "{\"hooks\": {\"codemap_refresh\": $val}}" > "${PROJECT_DIR}/.sentinel/config.json"
}

@test "exits gracefully when vault missing" {
    rm -rf "${PROJECT_DIR}/vault"
    run_hook "$HOOK" cwd="$PROJECT_DIR" source=startup
    assert_success
    assert_output ""
}

@test "no-op when source is not startup or resume" {
    write_config true
    run_hook "$HOOK" cwd="$PROJECT_DIR" source=clear
    assert_success
    assert_output ""
}

@test "no-op when codemap_refresh flag is false" {
    write_config false
    sleep 1; echo 'def f(): return 1' > src/a.py  # induce drift
    run_hook "$HOOK" cwd="$PROJECT_DIR" source=startup
    assert_success
    assert_output ""
}

@test "no-op when API key is missing" {
    write_config true
    sleep 1; echo 'def f(): return 1' > src/a.py
    local saved="${ANTHROPIC_API_KEY:-}"
    unset ANTHROPIC_API_KEY
    run_hook "$HOOK" cwd="$PROJECT_DIR" source=startup
    [ -n "$saved" ] && export ANTHROPIC_API_KEY="$saved"
    assert_success
    assert_output ""
}

@test "no-op when no manifests exist" {
    write_config true
    rm "${PROJECT_DIR}/vault/codemap/.manifest.json"
    ANTHROPIC_API_KEY=fake run_hook "$HOOK" cwd="$PROJECT_DIR" source=startup
    assert_success
    assert_output ""
}

@test "no-op when manifests exist but no drift" {
    write_config true
    ANTHROPIC_API_KEY=fake run_hook "$HOOK" cwd="$PROJECT_DIR" source=startup
    assert_success
    assert_output ""
}

@test "spawns worker and prints context message when drift detected" {
    write_config true
    sleep 1; echo 'def f(): return 1' > src/a.py  # induce drift
    ANTHROPIC_API_KEY=fake run_hook "$HOOK" cwd="$PROJECT_DIR" source=startup
    assert_success
    [[ "$output" == *"codemap entries are being refreshed"* ]]
}

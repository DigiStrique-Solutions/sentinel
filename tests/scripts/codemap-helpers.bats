#!/usr/bin/env bats

load "${BATS_TEST_DIRNAME}/../helpers/common"

SCRIPT="${SENTINEL_ROOT}/scripts/codemap-helpers.sh"

setup() {
    export PROJECT_DIR="${BATS_TEST_TMPDIR}/project"
    mkdir -p "$PROJECT_DIR"/{src/auth,src/api,vault/codemap/results}
    cd "$PROJECT_DIR"

    echo 'def login(): pass'  > src/auth/login.py
    echo 'def logout(): pass' > src/auth/logout.py
    echo 'def health(): pass' > src/api/health.py
    echo 'old login'  > vault/codemap/results/src--auth--login.py.md
    echo 'old logout' > vault/codemap/results/src--auth--logout.py.md
    echo 'old health' > vault/codemap/results/src--api--health.py.md
}

teardown() {
    cd / # ensure no stale CWD references
}

@test "register builds manifest from existing batch output" {
    CODEMAP_PROJECT_ROOT="$PROJECT_DIR" run bash "$SCRIPT" register \
        "${PROJECT_DIR}/vault/codemap" "test task" "src/**/*.py" "claude-haiku-4-5"
    assert_success
    [ -f "${PROJECT_DIR}/vault/codemap/.manifest.json" ]
    local entry_count
    entry_count=$(jq '.entries | length' "${PROJECT_DIR}/vault/codemap/.manifest.json")
    [ "$entry_count" = "3" ]
}

@test "register stores entry_path as results/<filename> when results/ subdir exists" {
    CODEMAP_PROJECT_ROOT="$PROJECT_DIR" bash "$SCRIPT" register \
        "${PROJECT_DIR}/vault/codemap" "task" "src/**/*.py" "claude-haiku-4-5" >/dev/null
    local entry_path
    entry_path=$(jq -r '.entries["src/auth/login.py"].entry_path' "${PROJECT_DIR}/vault/codemap/.manifest.json")
    [ "$entry_path" = "results/src--auth--login.py.md" ]
}

@test "register stores entry_path as bare filename for flat layout" {
    # Move files out of results/ to simulate flat layout
    mv vault/codemap/results/*.md vault/codemap/
    rmdir vault/codemap/results
    CODEMAP_PROJECT_ROOT="$PROJECT_DIR" bash "$SCRIPT" register \
        "${PROJECT_DIR}/vault/codemap" "task" "src/**/*.py" "claude-haiku-4-5" >/dev/null
    local entry_path
    entry_path=$(jq -r '.entries["src/auth/login.py"].entry_path' "${PROJECT_DIR}/vault/codemap/.manifest.json")
    [ "$entry_path" = "src--auth--login.py.md" ]
}

@test "register marks unmatched files as orphans" {
    # Add an entry file with no matching source
    echo 'orphan' > vault/codemap/results/src--gone.py.md
    CODEMAP_PROJECT_ROOT="$PROJECT_DIR" run bash "$SCRIPT" register \
        "${PROJECT_DIR}/vault/codemap" "task" "src/**/*.py" "claude-haiku-4-5"
    assert_success
    echo "$output" | jq -e '.unmatched_files | length == 1' >/dev/null
}

@test "detect-drift returns empty when nothing has changed" {
    CODEMAP_PROJECT_ROOT="$PROJECT_DIR" bash "$SCRIPT" register \
        "${PROJECT_DIR}/vault/codemap" "task" "src/**/*.py" "claude-haiku-4-5" >/dev/null
    run bash -c "CODEMAP_PROJECT_ROOT='$PROJECT_DIR' bash '$SCRIPT' detect-drift '${PROJECT_DIR}/vault/codemap/.manifest.json'"
    assert_success
    echo "$output" | jq -e '.modified | length == 0' >/dev/null
    echo "$output" | jq -e '.added | length == 0' >/dev/null
    echo "$output" | jq -e '.deleted | length == 0' >/dev/null
}

@test "detect-drift identifies modified source files" {
    CODEMAP_PROJECT_ROOT="$PROJECT_DIR" bash "$SCRIPT" register \
        "${PROJECT_DIR}/vault/codemap" "task" "src/**/*.py" "claude-haiku-4-5" >/dev/null
    sleep 1 # so mtime is strictly greater than generated_at
    echo 'def login(mfa): pass' > src/auth/login.py
    run bash -c "CODEMAP_PROJECT_ROOT='$PROJECT_DIR' bash '$SCRIPT' detect-drift '${PROJECT_DIR}/vault/codemap/.manifest.json'"
    assert_success
    echo "$output" | jq -e '.modified == ["src/auth/login.py"]' >/dev/null
}

@test "detect-drift identifies deleted source files" {
    CODEMAP_PROJECT_ROOT="$PROJECT_DIR" bash "$SCRIPT" register \
        "${PROJECT_DIR}/vault/codemap" "task" "src/**/*.py" "claude-haiku-4-5" >/dev/null
    rm src/api/health.py
    run bash -c "CODEMAP_PROJECT_ROOT='$PROJECT_DIR' bash '$SCRIPT' detect-drift '${PROJECT_DIR}/vault/codemap/.manifest.json'"
    assert_success
    echo "$output" | jq -e '.deleted == ["src/api/health.py"]' >/dev/null
}

@test "detect-drift identifies added files matching target_glob" {
    CODEMAP_PROJECT_ROOT="$PROJECT_DIR" bash "$SCRIPT" register \
        "${PROJECT_DIR}/vault/codemap" "task" "src/**/*.py" "claude-haiku-4-5" >/dev/null
    mkdir -p src/users
    echo 'def profile(): pass' > src/users/profile.py
    run bash -c "CODEMAP_PROJECT_ROOT='$PROJECT_DIR' bash '$SCRIPT' detect-drift '${PROJECT_DIR}/vault/codemap/.manifest.json'"
    assert_success
    echo "$output" | jq -e '.added == ["src/users/profile.py"]' >/dev/null
}

@test "detect-drift-files limits scope to paths in the file" {
    CODEMAP_PROJECT_ROOT="$PROJECT_DIR" bash "$SCRIPT" register \
        "${PROJECT_DIR}/vault/codemap" "task" "src/**/*.py" "claude-haiku-4-5" >/dev/null
    sleep 1
    # Modify TWO files but only one is in the scope file
    echo 'def login(mfa): pass'  > src/auth/login.py
    echo 'def logout(now): pass' > src/auth/logout.py
    mkdir -p .sentinel
    echo "src/auth/login.py" > .sentinel/scope.txt
    run bash -c "CODEMAP_PROJECT_ROOT='$PROJECT_DIR' bash '$SCRIPT' detect-drift-files '${PROJECT_DIR}/vault/codemap/.manifest.json' '${PROJECT_DIR}/.sentinel/scope.txt'"
    assert_success
    # Only login.py should be reported, not logout.py
    echo "$output" | jq -e '.modified == ["src/auth/login.py"]' >/dev/null
    # And scoped mode never reports adds
    echo "$output" | jq -e '.added == []' >/dev/null
}

@test "list-manifests finds all .manifest.json files under vault/" {
    CODEMAP_PROJECT_ROOT="$PROJECT_DIR" bash "$SCRIPT" register \
        "${PROJECT_DIR}/vault/codemap" "task" "src/**/*.py" "claude-haiku-4-5" >/dev/null
    # Create a second codemap
    mkdir -p "${PROJECT_DIR}/vault/api-docs"
    echo '{}' > "${PROJECT_DIR}/vault/api-docs/.manifest.json"
    run bash "$SCRIPT" list-manifests "$PROJECT_DIR"
    assert_success
    [ "$(echo "$output" | wc -l | tr -d ' ')" = "2" ]
}

@test "list-manifests returns empty when vault/ is missing" {
    rm -rf "${PROJECT_DIR}/vault"
    run bash "$SCRIPT" list-manifests "$PROJECT_DIR"
    assert_success
    [ -z "$output" ]
}

@test "status prints summary including drift counts" {
    CODEMAP_PROJECT_ROOT="$PROJECT_DIR" bash "$SCRIPT" register \
        "${PROJECT_DIR}/vault/codemap" "task" "src/**/*.py" "claude-haiku-4-5" >/dev/null
    rm src/api/health.py
    run bash -c "CODEMAP_PROJECT_ROOT='$PROJECT_DIR' bash '$SCRIPT' status '${PROJECT_DIR}/vault/codemap/.manifest.json'"
    assert_success
    [[ "$output" == *"Entries: 3"* ]]
    [[ "$output" == *"1 deleted"* ]]
    [[ "$output" == *"src/api/health.py"* ]]
}

@test "unknown subcommand returns non-zero exit" {
    run bash "$SCRIPT" not-a-real-subcommand
    [ "$status" -ne 0 ]
}

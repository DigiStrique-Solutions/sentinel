#!/usr/bin/env bats

load "${BATS_TEST_DIRNAME}/../helpers/common"

SCRIPT="${SENTINEL_ROOT}/scripts/configure-permissions.sh"

setup() {
    export PROJECT_DIR="${BATS_TEST_TMPDIR}/project"
    mkdir -p "$PROJECT_DIR"
}

# --- Basic execution ---

@test "creates .claude/settings.json when it does not exist" {
    run bash "$SCRIPT" "$PROJECT_DIR" "python"
    assert_success
    assert_file_exists "${PROJECT_DIR}/.claude/settings.json"
}

@test "returns count of permissions configured" {
    run bash "$SCRIPT" "$PROJECT_DIR" "python"
    assert_success
    # Should output a number
    [[ "$output" =~ ^[0-9]+$ ]]
    # Should be a reasonable number of permissions (> 30)
    [ "$output" -gt 30 ]
}

# --- Stack-specific permissions ---

@test "python stack includes pytest permissions" {
    run bash "$SCRIPT" "$PROJECT_DIR" "python"
    assert_success
    local settings
    settings=$(cat "${PROJECT_DIR}/.claude/settings.json")
    echo "$settings" | jq -e '.permissions.allow | map(select(contains("pytest"))) | length > 0'
}

@test "python stack includes ruff permissions" {
    run bash "$SCRIPT" "$PROJECT_DIR" "python"
    assert_success
    local settings
    settings=$(cat "${PROJECT_DIR}/.claude/settings.json")
    echo "$settings" | jq -e '.permissions.allow | map(select(contains("ruff"))) | length > 0'
}

@test "python stack does not include npm permissions" {
    run bash "$SCRIPT" "$PROJECT_DIR" "python"
    assert_success
    local settings
    settings=$(cat "${PROJECT_DIR}/.claude/settings.json")
    local npm_count
    npm_count=$(echo "$settings" | jq '[.permissions.allow[] | select(contains("npm"))] | length')
    [ "$npm_count" -eq 0 ]
}

@test "typescript stack includes npm permissions" {
    run bash "$SCRIPT" "$PROJECT_DIR" "typescript"
    assert_success
    local settings
    settings=$(cat "${PROJECT_DIR}/.claude/settings.json")
    echo "$settings" | jq -e '.permissions.allow | map(select(contains("npm"))) | length > 0'
}

@test "typescript stack includes eslint permissions" {
    run bash "$SCRIPT" "$PROJECT_DIR" "typescript"
    assert_success
    local settings
    settings=$(cat "${PROJECT_DIR}/.claude/settings.json")
    echo "$settings" | jq -e '.permissions.allow | map(select(contains("eslint"))) | length > 0'
}

@test "typescript stack does not include pytest permissions" {
    run bash "$SCRIPT" "$PROJECT_DIR" "typescript"
    assert_success
    local settings
    settings=$(cat "${PROJECT_DIR}/.claude/settings.json")
    local pytest_count
    pytest_count=$(echo "$settings" | jq '[.permissions.allow[] | select(contains("pytest"))] | length')
    [ "$pytest_count" -eq 0 ]
}

@test "both stack includes python and typescript permissions" {
    run bash "$SCRIPT" "$PROJECT_DIR" "both"
    assert_success
    local settings
    settings=$(cat "${PROJECT_DIR}/.claude/settings.json")
    echo "$settings" | jq -e '.permissions.allow | map(select(contains("pytest"))) | length > 0'
    echo "$settings" | jq -e '.permissions.allow | map(select(contains("npm"))) | length > 0'
}

@test "other stack includes all permissions" {
    run bash "$SCRIPT" "$PROJECT_DIR" "other"
    assert_success
    local settings
    settings=$(cat "${PROJECT_DIR}/.claude/settings.json")
    echo "$settings" | jq -e '.permissions.allow | map(select(contains("pytest"))) | length > 0'
    echo "$settings" | jq -e '.permissions.allow | map(select(contains("npm"))) | length > 0'
}

# --- Common permissions (all stacks) ---

@test "all stacks include git permissions" {
    run bash "$SCRIPT" "$PROJECT_DIR" "python"
    assert_success
    local settings
    settings=$(cat "${PROJECT_DIR}/.claude/settings.json")
    echo "$settings" | jq -e '.permissions.allow | map(select(contains("git status"))) | length > 0'
    echo "$settings" | jq -e '.permissions.allow | map(select(contains("git diff"))) | length > 0'
    echo "$settings" | jq -e '.permissions.allow | map(select(contains("git commit"))) | length > 0'
}

@test "all stacks include file operation permissions" {
    run bash "$SCRIPT" "$PROJECT_DIR" "typescript"
    assert_success
    local settings
    settings=$(cat "${PROJECT_DIR}/.claude/settings.json")
    echo "$settings" | jq -e '.permissions.allow | map(select(contains("mkdir"))) | length > 0'
    echo "$settings" | jq -e '.permissions.allow | map(select(contains("ls"))) | length > 0'
}

# --- Merge behavior ---

@test "merges with existing settings.json without overwriting" {
    mkdir -p "${PROJECT_DIR}/.claude"
    cat > "${PROJECT_DIR}/.claude/settings.json" <<'EOF'
{
  "permissions": {
    "allow": ["Bash(custom-command *)"]
  },
  "other_setting": true
}
EOF

    run bash "$SCRIPT" "$PROJECT_DIR" "python"
    assert_success

    local settings
    settings=$(cat "${PROJECT_DIR}/.claude/settings.json")
    # Preserves existing permission
    echo "$settings" | jq -e '.permissions.allow | map(select(contains("custom-command"))) | length > 0'
    # Adds new permissions
    echo "$settings" | jq -e '.permissions.allow | map(select(contains("pytest"))) | length > 0'
    # Preserves other settings
    echo "$settings" | jq -e '.other_setting == true'
}

@test "deduplicates permissions on repeated runs" {
    run bash "$SCRIPT" "$PROJECT_DIR" "python"
    assert_success
    local count1
    count1=$(cat "${PROJECT_DIR}/.claude/settings.json" | jq '.permissions.allow | length')

    run bash "$SCRIPT" "$PROJECT_DIR" "python"
    assert_success
    local count2
    count2=$(cat "${PROJECT_DIR}/.claude/settings.json" | jq '.permissions.allow | length')

    # Count should not grow on second run
    [ "$count1" -eq "$count2" ]
}

# --- Valid JSON output ---

@test "output is valid JSON" {
    run bash "$SCRIPT" "$PROJECT_DIR" "both"
    assert_success
    # settings.json should be valid JSON
    jq . "${PROJECT_DIR}/.claude/settings.json" > /dev/null 2>&1
}

@test "permissions.allow is a non-empty array" {
    run bash "$SCRIPT" "$PROJECT_DIR" "python"
    assert_success
    local length
    length=$(cat "${PROJECT_DIR}/.claude/settings.json" | jq '.permissions.allow | length')
    [ "$length" -gt 0 ]
}

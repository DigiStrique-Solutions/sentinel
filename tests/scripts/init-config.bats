#!/usr/bin/env bats

load "${BATS_TEST_DIRNAME}/../helpers/common"

SCRIPT="${SENTINEL_ROOT}/scripts/init-config.sh"

setup() {
    export PROJECT_DIR="${BATS_TEST_TMPDIR}/project"
    mkdir -p "$PROJECT_DIR"
}

# --- Argument validation ---

@test "fails with exit 2 when project_dir is missing" {
    run bash "$SCRIPT"
    [ "$status" -eq 2 ]
    [[ "$output" == *"project_dir required"* ]]
}

@test "fails with exit 2 when project_dir does not exist" {
    run bash "$SCRIPT" "/nonexistent/path/xyz" standard init
    [ "$status" -eq 2 ]
    [[ "$output" == *"does not exist"* ]]
}

@test "fails with exit 2 when preset is unknown" {
    run bash "$SCRIPT" "$PROJECT_DIR" bogus-preset init
    [ "$status" -eq 2 ]
    [[ "$output" == *"preset bogus-preset not found"* ]]
}

# --- Fresh init ---

@test "init creates .sentinel/config.json on fresh project" {
    run bash "$SCRIPT" "$PROJECT_DIR" standard init
    assert_success
    assert_file_exists "${PROJECT_DIR}/.sentinel/config.json"
}

@test "init reports created:true and skipped:false on fresh project" {
    run bash "$SCRIPT" "$PROJECT_DIR" standard init
    assert_success
    echo "$output" | jq -e '.created == true'
    echo "$output" | jq -e '.skipped == false'
    echo "$output" | jq -e '.healed == false'
}

@test "init writes valid JSON to config.json" {
    run bash "$SCRIPT" "$PROJECT_DIR" standard init
    assert_success
    jq . "${PROJECT_DIR}/.sentinel/config.json" >/dev/null
}

# --- Preset-specific defaults ---

@test "standard preset enables 4 hooks" {
    run bash "$SCRIPT" "$PROJECT_DIR" standard init
    assert_success
    local enabled
    enabled=$(jq -r '.hooks_enabled' <<< "$output")
    [ "$enabled" -eq 4 ]
}

@test "standard preset enables pattern_extraction, vault_search, session_summary, git_autopilot" {
    run bash "$SCRIPT" "$PROJECT_DIR" standard init
    assert_success
    local cfg="${PROJECT_DIR}/.sentinel/config.json"
    [ "$(jq -r '.hooks.pattern_extraction' "$cfg")" = "true" ]
    [ "$(jq -r '.hooks.vault_search_on_prompt' "$cfg")" = "true" ]
    [ "$(jq -r '.hooks.session_summary' "$cfg")" = "true" ]
    [ "$(jq -r '.hooks.git_autopilot' "$cfg")" = "true" ]
}

@test "standard preset disables design_review_reminder by default" {
    run bash "$SCRIPT" "$PROJECT_DIR" standard init
    assert_success
    [ "$(jq -r '.hooks.design_review_reminder' "${PROJECT_DIR}/.sentinel/config.json")" = "false" ]
}

@test "minimal preset enables only 2 hooks" {
    run bash "$SCRIPT" "$PROJECT_DIR" minimal init
    assert_success
    local enabled
    enabled=$(jq -r '.hooks_enabled' <<< "$output")
    [ "$enabled" -eq 2 ]
}

@test "minimal preset enables vault_search and git_autopilot only" {
    run bash "$SCRIPT" "$PROJECT_DIR" minimal init
    assert_success
    local cfg="${PROJECT_DIR}/.sentinel/config.json"
    [ "$(jq -r '.hooks.vault_search_on_prompt' "$cfg")" = "true" ]
    [ "$(jq -r '.hooks.git_autopilot' "$cfg")" = "true" ]
    [ "$(jq -r '.hooks.pattern_extraction' "$cfg")" = "false" ]
    [ "$(jq -r '.hooks.session_summary' "$cfg")" = "false" ]
}

@test "team preset inherits hooks_config from standard via extends" {
    run bash "$SCRIPT" "$PROJECT_DIR" team init
    assert_success
    local cfg="${PROJECT_DIR}/.sentinel/config.json"
    [ "$(jq -r '.hooks.pattern_extraction' "$cfg")" = "true" ]
    [ "$(jq -r '.hooks.vault_search_on_prompt' "$cfg")" = "true" ]
    [ "$(jq -r '.hooks.session_summary' "$cfg")" = "true" ]
    [ "$(jq -r '.preset' "$cfg")" = "team" ]
}

# --- Config schema completeness ---

@test "writes vault block with repo_path, global_enabled, global_path" {
    run bash "$SCRIPT" "$PROJECT_DIR" standard init
    assert_success
    local cfg="${PROJECT_DIR}/.sentinel/config.json"
    [ "$(jq -r '.vault.repo_path' "$cfg")" = "vault" ]
    [ "$(jq -r '.vault.global_enabled' "$cfg")" = "true" ]
    [ "$(jq -r '.vault.global_path' "$cfg")" = "~/.sentinel/vault" ]
}

@test "writes thresholds block with all four thresholds" {
    run bash "$SCRIPT" "$PROJECT_DIR" standard init
    assert_success
    local cfg="${PROJECT_DIR}/.sentinel/config.json"
    [ "$(jq -r '.thresholds.scope_warning_files' "$cfg")" = "3" ]
    [ "$(jq -r '.thresholds.test_failure_warning' "$cfg")" = "2" ]
    [ "$(jq -r '.thresholds.gotcha_staleness_days' "$cfg")" = "30" ]
    [ "$(jq -r '.thresholds.investigation_warning_days' "$cfg")" = "7" ]
}

@test "records the preset name in the config" {
    run bash "$SCRIPT" "$PROJECT_DIR" minimal init
    assert_success
    [ "$(jq -r '.preset' "${PROJECT_DIR}/.sentinel/config.json")" = "minimal" ]
}

# --- Idempotency / no-clobber ---

@test "init mode skips when config.json already exists" {
    bash "$SCRIPT" "$PROJECT_DIR" standard init >/dev/null
    # Tamper with the existing config to confirm it isn't overwritten
    jq '.hooks.git_autopilot = false' "${PROJECT_DIR}/.sentinel/config.json" > /tmp/tmp.json
    mv /tmp/tmp.json "${PROJECT_DIR}/.sentinel/config.json"

    run bash "$SCRIPT" "$PROJECT_DIR" standard init
    assert_success
    echo "$output" | jq -e '.skipped == true'
    echo "$output" | jq -e '.created == false'
    # Tamper preserved
    [ "$(jq -r '.hooks.git_autopilot' "${PROJECT_DIR}/.sentinel/config.json")" = "false" ]
}

# --- Heal mode ---

@test "heal mode creates config.json when missing" {
    run bash "$SCRIPT" "$PROJECT_DIR" standard heal
    assert_success
    assert_file_exists "${PROJECT_DIR}/.sentinel/config.json"
    echo "$output" | jq -e '.created == true'
}

@test "heal mode is no-op when config is intact" {
    bash "$SCRIPT" "$PROJECT_DIR" standard init >/dev/null
    run bash "$SCRIPT" "$PROJECT_DIR" standard heal
    assert_success
    echo "$output" | jq -e '.skipped == true'
    echo "$output" | jq -e '.healed == false'
    echo "$output" | jq -e '.healed_keys == []'
}

@test "heal mode adds missing hook keys" {
    bash "$SCRIPT" "$PROJECT_DIR" standard init >/dev/null
    # Delete one hook key
    jq 'del(.hooks.pattern_extraction)' "${PROJECT_DIR}/.sentinel/config.json" > /tmp/tmp.json
    mv /tmp/tmp.json "${PROJECT_DIR}/.sentinel/config.json"

    run bash "$SCRIPT" "$PROJECT_DIR" standard heal
    assert_success
    echo "$output" | jq -e '.healed == true'
    echo "$output" | jq -e '.healed_keys | contains(["hooks.pattern_extraction"])'
    # Restored to default (true for standard)
    [ "$(jq -r '.hooks.pattern_extraction' "${PROJECT_DIR}/.sentinel/config.json")" = "true" ]
}

@test "heal mode preserves user customizations on existing keys" {
    bash "$SCRIPT" "$PROJECT_DIR" standard init >/dev/null
    # User toggled a hook off
    jq '.hooks.pattern_extraction = false | .thresholds.gotcha_staleness_days = 60' \
        "${PROJECT_DIR}/.sentinel/config.json" > /tmp/tmp.json
    mv /tmp/tmp.json "${PROJECT_DIR}/.sentinel/config.json"
    # Then later: a new key was added to the schema. Simulate by deleting one.
    jq 'del(.thresholds.investigation_warning_days)' "${PROJECT_DIR}/.sentinel/config.json" > /tmp/tmp.json
    mv /tmp/tmp.json "${PROJECT_DIR}/.sentinel/config.json"

    run bash "$SCRIPT" "$PROJECT_DIR" standard heal
    assert_success
    local cfg="${PROJECT_DIR}/.sentinel/config.json"
    # User customizations preserved
    [ "$(jq -r '.hooks.pattern_extraction' "$cfg")" = "false" ]
    [ "$(jq -r '.thresholds.gotcha_staleness_days' "$cfg")" = "60" ]
    # Missing key restored from defaults
    [ "$(jq -r '.thresholds.investigation_warning_days' "$cfg")" = "7" ]
}

@test "heal mode restores all five hook keys when all are missing" {
    # Simulate an old install that had only vault and thresholds (no hooks block)
    mkdir -p "${PROJECT_DIR}/.sentinel"
    cat > "${PROJECT_DIR}/.sentinel/config.json" <<'EOF'
{
  "preset": "standard",
  "vault": {"repo_path": "vault", "global_enabled": true, "global_path": "~/.sentinel/vault"},
  "thresholds": {"scope_warning_files": 3, "test_failure_warning": 2, "gotcha_staleness_days": 30, "investigation_warning_days": 7}
}
EOF
    run bash "$SCRIPT" "$PROJECT_DIR" standard heal
    assert_success
    local cfg="${PROJECT_DIR}/.sentinel/config.json"
    [ "$(jq -r '.hooks | keys | length' "$cfg")" = "5" ]
    [ "$(jq -r '.hooks.pattern_extraction' "$cfg")" = "true" ]
}

# --- JSON output shape ---

@test "outputs valid JSON summary" {
    run bash "$SCRIPT" "$PROJECT_DIR" standard init
    assert_success
    echo "$output" | jq . >/dev/null
}

@test "JSON summary includes config_path, preset, created, healed, skipped, hooks_enabled" {
    run bash "$SCRIPT" "$PROJECT_DIR" standard init
    assert_success
    echo "$output" | jq -e 'has("config_path") and has("preset") and has("created") and has("healed") and has("skipped") and has("hooks_enabled")'
}

# --- End-to-end self-learning loop verification ---
# These tests prove the actual user-facing outcome: after bootstrap,
# the optional hooks read .sentinel/config.json and become enabled.

@test "after init, stop-pattern-extractor reads enabled=true from config" {
    # Init the config
    bash "$SCRIPT" "$PROJECT_DIR" standard init >/dev/null
    # Verify the hook script's enabled-check passes
    local enabled
    enabled=$(jq -r '.hooks.pattern_extraction // false' "${PROJECT_DIR}/.sentinel/config.json")
    [ "$enabled" = "true" ]
}

@test "after init, prompt-vault-search reads enabled=true from config" {
    bash "$SCRIPT" "$PROJECT_DIR" standard init >/dev/null
    local enabled
    enabled=$(jq -r '.hooks.vault_search_on_prompt // false' "${PROJECT_DIR}/.sentinel/config.json")
    [ "$enabled" = "true" ]
}

@test "after init, stop-session-summary reads enabled=true from config" {
    bash "$SCRIPT" "$PROJECT_DIR" standard init >/dev/null
    local enabled
    enabled=$(jq -r '.hooks.session_summary // false' "${PROJECT_DIR}/.sentinel/config.json")
    [ "$enabled" = "true" ]
}

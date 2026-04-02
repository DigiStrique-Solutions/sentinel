#!/usr/bin/env bats

load "${BATS_TEST_DIRNAME}/../helpers/common"

HOOK="${SENTINEL_ROOT}/hooks/engine/session-start-loader.sh"

setup() {
    export PROJECT_DIR="${BATS_TEST_TMPDIR}/project"
    mkdir -p "$PROJECT_DIR"
    VAULT_DIR=$(create_test_vault "$PROJECT_DIR")
    init_test_git_repo "$PROJECT_DIR"
}

# --- Graceful exits ---

@test "exits gracefully when vault dir missing" {
    rm -rf "${PROJECT_DIR}/vault"
    run_hook "$HOOK" cwd="$PROJECT_DIR"
    assert_success
    assert_output ""
}

@test "empty vault produces no output" {
    # Vault exists but all directories are empty
    run_hook "$HOOK" cwd="$PROJECT_DIR"
    assert_success
    assert_output ""
}

# --- Priority 1: Open investigations ---

@test "loads open investigations into context" {
    create_investigation "$VAULT_DIR" "2026-04-bug.md" "open"
    run_hook "$HOOK" cwd="$PROJECT_DIR"
    assert_success
    assert_output --partial "OPEN INVESTIGATIONS"
    assert_output --partial "2026-04-bug.md"
}

@test "skips resolved investigations" {
    create_investigation "$VAULT_DIR" "2026-04-fixed.md" "resolved"
    run_hook "$HOOK" cwd="$PROJECT_DIR"
    assert_success
    refute_output --partial "2026-04-fixed.md"
}

@test "skips implemented investigations" {
    create_investigation "$VAULT_DIR" "2026-04-done.md" "implemented"
    run_hook "$HOOK" cwd="$PROJECT_DIR"
    assert_success
    refute_output --partial "2026-04-done.md"
}

@test "skips obsolete investigations" {
    create_investigation "$VAULT_DIR" "2026-04-old.md" "obsolete"
    run_hook "$HOOK" cwd="$PROJECT_DIR"
    assert_success
    refute_output --partial "2026-04-old.md"
}

@test "skips _template.md in investigations" {
    create_investigation "$VAULT_DIR" "_template.md" "open"
    run_hook "$HOOK" cwd="$PROJECT_DIR"
    assert_success
    refute_output --partial "_template.md"
}

@test "counts resolved investigations without loading content" {
    mkdir -p "${VAULT_DIR}/investigations/resolved"
    echo "resolved content" > "${VAULT_DIR}/investigations/resolved/old-bug.md"
    echo "more resolved" > "${VAULT_DIR}/investigations/resolved/another.md"
    # Need at least one open investigation to trigger output
    create_investigation "$VAULT_DIR" "2026-04-current.md" "open"
    run_hook "$HOOK" cwd="$PROJECT_DIR"
    assert_success
    assert_output --partial "2 resolved investigations"
    refute_output --partial "resolved content"
}

# --- Priority 2: Gotchas ---

@test "loads gotchas into context" {
    create_gotcha "$VAULT_DIR" "test-gotcha.md" "Test Gotcha"
    run_hook "$HOOK" cwd="$PROJECT_DIR"
    assert_success
    assert_output --partial "KNOWN GOTCHAS"
    assert_output --partial "test-gotcha"
}

@test "loads relevant gotchas matching git diff" {
    # Create a file in src/auth/ and commit, then create a gotcha mentioning auth
    mkdir -p "${PROJECT_DIR}/src/auth"
    echo "code" > "${PROJECT_DIR}/src/auth/login.py"
    cd "$PROJECT_DIR" && git add -A && git commit -q -m "add auth" && cd - > /dev/null
    create_gotcha "$VAULT_DIR" "auth-gotcha.md" "Auth Gotcha" "Watch out for src/auth edge cases"
    create_gotcha "$VAULT_DIR" "unrelated.md" "Unrelated Gotcha" "Something about billing"
    run_hook "$HOOK" cwd="$PROJECT_DIR"
    assert_success
    assert_output --partial "auth-gotcha"
}

# --- Priority 3: Session recovery ---

@test "loads recent session recovery" {
    create_recovery "$VAULT_DIR" "2026-04-02T10-00-00.md" 30
    run_hook "$HOOK" cwd="$PROJECT_DIR"
    assert_success
    assert_output --partial "SESSION RECOVERY"
}

@test "skips old session recovery" {
    create_recovery "$VAULT_DIR" "2026-04-02T10-00-00.md" 180
    run_hook "$HOOK" cwd="$PROJECT_DIR"
    assert_success
    refute_output --partial "SESSION RECOVERY"
}

# --- Priority 4: Learned patterns ---

@test "loads high-confidence patterns" {
    create_pattern "$VAULT_DIR" "good-pattern.md" "0.85"
    run_hook "$HOOK" cwd="$PROJECT_DIR"
    assert_success
    assert_output --partial "LEARNED PATTERNS"
    assert_output --partial "good-pattern"
}

@test "skips low-confidence patterns" {
    create_pattern "$VAULT_DIR" "weak-pattern.md" "0.3"
    run_hook "$HOOK" cwd="$PROJECT_DIR"
    assert_success
    refute_output --partial "weak-pattern"
}

@test "handles empty confidence field gracefully" {
    cat > "${VAULT_DIR}/patterns/learned/empty-conf.md" <<'EOF'
confidence:
observations: 1

# Empty Confidence
EOF
    run_hook "$HOOK" cwd="$PROJECT_DIR"
    assert_success
    refute_output --partial "empty-conf"
}

@test "handles non-numeric confidence gracefully" {
    cat > "${VAULT_DIR}/patterns/learned/bad-conf.md" <<'EOF'
confidence: high
observations: 1

# Bad Confidence
EOF
    run_hook "$HOOK" cwd="$PROJECT_DIR"
    assert_success
    refute_output --partial "bad-conf"
}

# --- Priority 5: Team activity ---

@test "loads team activity for recent days" {
    local today
    today=$(date +%Y-%m-%d)
    create_activity "$VAULT_DIR" "$today" "- Fixed a bug in auth"
    run_hook "$HOOK" cwd="$PROJECT_DIR"
    assert_success
    assert_output --partial "TEAM ACTIVITY"
}

# --- Token budget ---

@test "custom SENTINEL_TOKEN_BUDGET respected" {
    # With a tiny budget, only highest-priority content loads
    create_investigation "$VAULT_DIR" "2026-04-bug.md" "open"
    create_gotcha "$VAULT_DIR" "gotcha.md" "A Gotcha"
    create_pattern "$VAULT_DIR" "pattern.md" "0.9"
    local today
    today=$(date +%Y-%m-%d)
    create_activity "$VAULT_DIR" "$today" "- Activity entry"

    export SENTINEL_TOKEN_BUDGET=50
    run_hook "$HOOK" cwd="$PROJECT_DIR"
    assert_success
    # Investigations are priority 1 — should appear
    assert_output --partial "OPEN INVESTIGATIONS"
    # Activity is priority 5 — likely skipped with 50 token budget
    unset SENTINEL_TOKEN_BUDGET
}

@test "budget reporting shows token count" {
    create_investigation "$VAULT_DIR" "2026-04-bug.md" "open"
    run_hook "$HOOK" cwd="$PROJECT_DIR"
    assert_success
    assert_output --partial "tokens"
}

# --- Team onboarding ---

@test "shows onboarding nudge for new users" {
    # Create a manifest file
    mkdir -p "${PROJECT_DIR}/.claude/shared"
    echo '{}' > "${PROJECT_DIR}/.claude/shared/manifest.json"
    run_hook "$HOOK" cwd="$PROJECT_DIR"
    assert_success
    assert_output --partial "onboard"
}

@test "no onboarding nudge when already onboarded" {
    mkdir -p "${PROJECT_DIR}/.claude/shared"
    echo '{}' > "${PROJECT_DIR}/.claude/shared/manifest.json"
    # Create the onboarded marker
    mkdir -p "${PROJECT_DIR}/.sentinel"
    touch "${PROJECT_DIR}/.sentinel/onboarded-test-user"
    run_hook "$HOOK" cwd="$PROJECT_DIR"
    assert_success
    refute_output --partial "onboard"
}

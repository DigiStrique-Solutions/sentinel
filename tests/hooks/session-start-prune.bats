#!/usr/bin/env bats

load "${BATS_TEST_DIRNAME}/../helpers/common"

HOOK="${SENTINEL_ROOT}/hooks/engine/session-start-prune.sh"

setup() {
    export PROJECT_DIR="${BATS_TEST_TMPDIR}/project"
    mkdir -p "$PROJECT_DIR"
    VAULT_DIR=$(create_test_vault "$PROJECT_DIR")
}

# Helper: force session counter to a specific value so pruning runs
force_prune_session() {
    mkdir -p "${PROJECT_DIR}/.sentinel"
    echo "4" > "${PROJECT_DIR}/.sentinel/session-count"
}

# --- Session counter ---

@test "exits early for sessions 1-4 (not 5th)" {
    mkdir -p "${PROJECT_DIR}/.sentinel"
    echo "0" > "${PROJECT_DIR}/.sentinel/session-count"
    run_hook "$HOOK" cwd="$PROJECT_DIR"
    assert_success
    assert_output ""
}

@test "runs on every 5th session" {
    force_prune_session
    run_hook "$HOOK" cwd="$PROJECT_DIR"
    assert_success
    # Counter should now be 5
    local count
    count=$(cat "${PROJECT_DIR}/.sentinel/session-count")
    [ "$count" -eq 5 ]
}

@test "session counter increments correctly" {
    mkdir -p "${PROJECT_DIR}/.sentinel"
    echo "7" > "${PROJECT_DIR}/.sentinel/session-count"
    run_hook "$HOOK" cwd="$PROJECT_DIR"
    assert_success
    local count
    count=$(cat "${PROJECT_DIR}/.sentinel/session-count")
    [ "$count" -eq 8 ]
}

@test "graceful exit when vault missing" {
    rm -rf "${PROJECT_DIR}/vault"
    run_hook "$HOOK" cwd="$PROJECT_DIR"
    assert_success
    assert_output ""
}

# --- Tier 1: Auto-archive ---

@test "archives session recovery older than 7 days" {
    force_prune_session
    echo "old recovery" > "${VAULT_DIR}/session-recovery/old.md"
    set_file_age "${VAULT_DIR}/session-recovery/old.md" 10
    run_hook "$HOOK" cwd="$PROJECT_DIR"
    assert_success
    assert_file_not_exist "${VAULT_DIR}/session-recovery/old.md"
    assert_file_exist "${VAULT_DIR}/.archive/session-recovery/old.md"
}

@test "preserves session recovery 7 days or younger" {
    force_prune_session
    echo "recent recovery" > "${VAULT_DIR}/session-recovery/recent.md"
    set_file_age "${VAULT_DIR}/session-recovery/recent.md" 3
    run_hook "$HOOK" cwd="$PROJECT_DIR"
    assert_success
    assert_file_exist "${VAULT_DIR}/session-recovery/recent.md"
}

@test "archives resolved investigations older than 30 days" {
    force_prune_session
    echo "old resolved" > "${VAULT_DIR}/investigations/resolved/old.md"
    set_file_age "${VAULT_DIR}/investigations/resolved/old.md" 45
    run_hook "$HOOK" cwd="$PROJECT_DIR"
    assert_success
    assert_file_not_exist "${VAULT_DIR}/investigations/resolved/old.md"
    assert_file_exist "${VAULT_DIR}/.archive/investigations/resolved/old.md"
}

@test "preserves resolved investigations 30 days or younger" {
    force_prune_session
    echo "recent resolved" > "${VAULT_DIR}/investigations/resolved/recent.md"
    set_file_age "${VAULT_DIR}/investigations/resolved/recent.md" 15
    run_hook "$HOOK" cwd="$PROJECT_DIR"
    assert_success
    assert_file_exist "${VAULT_DIR}/investigations/resolved/recent.md"
}

@test "archives changelog older than 90 days" {
    force_prune_session
    echo "old changelog" > "${VAULT_DIR}/changelog/old-entry.md"
    set_file_age "${VAULT_DIR}/changelog/old-entry.md" 100
    run_hook "$HOOK" cwd="$PROJECT_DIR"
    assert_success
    assert_file_not_exist "${VAULT_DIR}/changelog/old-entry.md"
}

@test "archives superseded decisions" {
    force_prune_session
    cat > "${VAULT_DIR}/decisions/old-decision.md" <<'EOF'
---
status: superseded
---
# Old Decision
EOF
    run_hook "$HOOK" cwd="$PROJECT_DIR"
    assert_success
    assert_file_not_exist "${VAULT_DIR}/decisions/old-decision.md"
}

@test "archives deprecated decisions" {
    force_prune_session
    cat > "${VAULT_DIR}/decisions/deprecated.md" <<'EOF'
---
status: deprecated
---
# Deprecated Decision
EOF
    run_hook "$HOOK" cwd="$PROJECT_DIR"
    assert_success
    assert_file_not_exist "${VAULT_DIR}/decisions/deprecated.md"
}

@test "preserves active decisions" {
    force_prune_session
    cat > "${VAULT_DIR}/decisions/active.md" <<'EOF'
---
status: accepted
---
# Active Decision
EOF
    run_hook "$HOOK" cwd="$PROJECT_DIR"
    assert_success
    assert_file_exist "${VAULT_DIR}/decisions/active.md"
}

@test "archives activity files older than 30 days" {
    force_prune_session
    echo "old activity" > "${VAULT_DIR}/activity/old.md"
    set_file_age "${VAULT_DIR}/activity/old.md" 35
    run_hook "$HOOK" cwd="$PROJECT_DIR"
    assert_success
    assert_file_not_exist "${VAULT_DIR}/activity/old.md"
}

@test "archive preserves directory structure" {
    force_prune_session
    echo "deep file" > "${VAULT_DIR}/investigations/resolved/deep.md"
    set_file_age "${VAULT_DIR}/investigations/resolved/deep.md" 45
    run_hook "$HOOK" cwd="$PROJECT_DIR"
    assert_success
    assert_file_exist "${VAULT_DIR}/.archive/investigations/resolved/deep.md"
}

@test "ARCHIVED counter reports correctly" {
    force_prune_session
    echo "old1" > "${VAULT_DIR}/session-recovery/old1.md"
    echo "old2" > "${VAULT_DIR}/session-recovery/old2.md"
    set_file_age "${VAULT_DIR}/session-recovery/old1.md" 10
    set_file_age "${VAULT_DIR}/session-recovery/old2.md" 10
    run_hook "$HOOK" cwd="$PROJECT_DIR"
    assert_success
    assert_output --partial "Archived 2 stale"
}

# --- Tier 2: Auto-flag ---

@test "flags open investigations older than 60 days" {
    force_prune_session
    create_investigation "$VAULT_DIR" "ancient.md" "open"
    set_file_age "${VAULT_DIR}/investigations/ancient.md" 65
    run_hook "$HOOK" cwd="$PROJECT_DIR"
    assert_success
    assert_output --partial "ancient.md"
    assert_output --partial "review needed"
}

@test "flags gotchas with all dead references" {
    force_prune_session
    create_gotcha "$VAULT_DIR" "dead-refs.md" "Dead Gotcha" "See src/deleted/module.py for details"
    run_hook "$HOOK" cwd="$PROJECT_DIR"
    assert_success
    assert_output --partial "dead-refs.md"
    assert_output --partial "deleted"
}

@test "preserves gotchas with live references" {
    force_prune_session
    # Create a real file that the gotcha references
    mkdir -p "${PROJECT_DIR}/src"
    echo "code" > "${PROJECT_DIR}/src/real-file.py"
    create_gotcha "$VAULT_DIR" "live-refs.md" "Live Gotcha" "See src/real-file.py for details"
    run_hook "$HOOK" cwd="$PROJECT_DIR"
    assert_success
    refute_output --partial "live-refs.md"
}

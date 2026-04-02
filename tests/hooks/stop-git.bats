#!/usr/bin/env bats

load "${BATS_TEST_DIRNAME}/../helpers/common"

HOOK="${SENTINEL_ROOT}/hooks/engine/stop-git.sh"

setup() {
    export PROJECT_DIR="${BATS_TEST_TMPDIR}/project"
    mkdir -p "$PROJECT_DIR"
    init_test_git_repo "$PROJECT_DIR"
}

# --- Graceful exits ---

@test "exits when no changes" {
    run_hook "$HOOK" cwd="$PROJECT_DIR"
    assert_success
    assert_output ""
}

@test "exits when not a git repo" {
    local non_git="${BATS_TEST_TMPDIR}/non-git"
    mkdir -p "$non_git"
    run_hook "$HOOK" cwd="$non_git"
    assert_success
    assert_output ""
}

# --- Sensitive file exclusion ---

@test "excludes .env from staging" {
    cd "$PROJECT_DIR"
    echo "SECRET=xyz" > .env
    echo "code" > app.py
    cd - > /dev/null
    run_hook "$HOOK" cwd="$PROJECT_DIR"
    assert_success
    # .env should not be committed
    cd "$PROJECT_DIR"
    # Verify .env was NOT committed
    run git show --name-only HEAD
    refute_output --partial ".env"
    cd - > /dev/null
}

@test "excludes .pem files from staging" {
    cd "$PROJECT_DIR"
    echo "PRIVATE KEY" > server.pem
    echo "code" > app.py
    cd - > /dev/null
    run_hook "$HOOK" cwd="$PROJECT_DIR"
    assert_success
    cd "$PROJECT_DIR"
    run git show --name-only HEAD
    refute_output --partial ".pem"
    cd - > /dev/null
}

@test "excludes .sentinel/ from staging" {
    cd "$PROJECT_DIR"
    mkdir -p .sentinel
    echo "tracking" > .sentinel/state.json
    echo "code" > app.py
    cd - > /dev/null
    run_hook "$HOOK" cwd="$PROJECT_DIR"
    assert_success
    cd "$PROJECT_DIR"
    run git show --name-only HEAD
    refute_output --partial ".sentinel"
    cd - > /dev/null
}

# --- Commit creation ---

@test "commits remaining changes" {
    cd "$PROJECT_DIR"
    echo "new code" > feature.py
    cd - > /dev/null
    run_hook "$HOOK" cwd="$PROJECT_DIR"
    assert_success
    assert_output --partial "GIT AUTOPILOT"
    assert_output --partial "Committed"
}

# --- Commit type detection ---

@test "commit type feat for new files" {
    cd "$PROJECT_DIR"
    echo "new" > new-feature.py
    cd - > /dev/null
    run_hook "$HOOK" cwd="$PROJECT_DIR"
    assert_success
    assert_output --partial "feat:"
}

@test "commit type test for test-only modifications" {
    cd "$PROJECT_DIR"
    # Create and commit a test file first, then modify it
    echo "test v1" > test_auth.py
    git add test_auth.py && git commit -q -m "add test"
    # Now modify it (HAS_NEW=0, so test check can match)
    echo "test v2" > test_auth.py
    cd - > /dev/null
    run_hook "$HOOK" cwd="$PROJECT_DIR"
    assert_success
    assert_output --partial "test:"
}

@test "commit type docs for vault-only modifications" {
    cd "$PROJECT_DIR"
    mkdir -p vault/gotchas
    echo "gotcha v1" > vault/gotchas/gotcha.md
    git add -A && git commit -q -m "add gotcha"
    # Now modify it
    echo "gotcha v2" > vault/gotchas/gotcha.md
    cd - > /dev/null
    run_hook "$HOOK" cwd="$PROJECT_DIR"
    assert_success
    assert_output --partial "docs:"
}

@test "commit type chore as default" {
    cd "$PROJECT_DIR"
    echo "modified" >> README.md
    cd - > /dev/null
    run_hook "$HOOK" cwd="$PROJECT_DIR"
    assert_success
    assert_output --partial "chore:"
}

# --- Commit message ---

@test "file count in commit message when multiple files" {
    cd "$PROJECT_DIR"
    echo "a" > file1.py
    echo "b" > file2.py
    echo "c" > file3.py
    cd - > /dev/null
    run_hook "$HOOK" cwd="$PROJECT_DIR"
    assert_success
    assert_output --partial "3 files"
}

@test "areas extracted from file paths" {
    cd "$PROJECT_DIR"
    mkdir -p src
    echo "code" > src/app.py
    cd - > /dev/null
    run_hook "$HOOK" cwd="$PROJECT_DIR"
    assert_success
    assert_output --partial "src"
}

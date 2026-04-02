#!/usr/bin/env bats

load "${BATS_TEST_DIRNAME}/../helpers/common"

HOOK="${SENTINEL_ROOT}/hooks/engine/post-tool-impact.sh"
SESSION_ID="test-session-1234567890"
SHORT_ID="test-session"

setup() {
    export PROJECT_DIR="${BATS_TEST_TMPDIR}/project"
    mkdir -p "$PROJECT_DIR"
    init_test_git_repo "$PROJECT_DIR"
    mkdir -p "${PROJECT_DIR}/.sentinel/sessions/${SHORT_ID}"
}

get_impact() {
    cat "${PROJECT_DIR}/.sentinel/sessions/${SHORT_ID}/impact-tests.txt" 2>/dev/null || echo ""
}

# --- Filtering ---

@test "ignores test files" {
    run_hook "$HOOK" cwd="$PROJECT_DIR" session_id="$SESSION_ID" file_path="tests/test_auth.py"
    assert_success
    local impact
    impact=$(get_impact)
    [ -z "$impact" ]
}

@test "ignores spec files" {
    run_hook "$HOOK" cwd="$PROJECT_DIR" session_id="$SESSION_ID" file_path="src/auth.spec.ts"
    assert_success
    local impact
    impact=$(get_impact)
    [ -z "$impact" ]
}

@test "ignores markdown files" {
    run_hook "$HOOK" cwd="$PROJECT_DIR" session_id="$SESSION_ID" file_path="docs/README.md"
    assert_success
    local impact
    impact=$(get_impact)
    [ -z "$impact" ]
}

@test "ignores JSON config files" {
    run_hook "$HOOK" cwd="$PROJECT_DIR" session_id="$SESSION_ID" file_path="package.json"
    assert_success
    local impact
    impact=$(get_impact)
    [ -z "$impact" ]
}

@test "processes Python source files" {
    # Create a test file that imports the module
    mkdir -p "${PROJECT_DIR}/tests" "${PROJECT_DIR}/src"
    echo "code" > "${PROJECT_DIR}/src/auth.py"
    echo "from src.auth import login" > "${PROJECT_DIR}/tests/test_auth.py"
    run_hook "$HOOK" cwd="$PROJECT_DIR" session_id="$SESSION_ID" file_path="${PROJECT_DIR}/src/auth.py"
    assert_success
    local impact
    impact=$(get_impact)
    [[ "$impact" == *"test_auth.py"* ]]
}

@test "processes TypeScript source files" {
    mkdir -p "${PROJECT_DIR}/src" "${PROJECT_DIR}/src/__tests__"
    echo "code" > "${PROJECT_DIR}/src/Button.tsx"
    echo "import { Button } from '../Button'" > "${PROJECT_DIR}/src/__tests__/Button.test.tsx"
    run_hook "$HOOK" cwd="$PROJECT_DIR" session_id="$SESSION_ID" file_path="${PROJECT_DIR}/src/Button.tsx"
    assert_success
    local impact
    impact=$(get_impact)
    [[ "$impact" == *"Button.test.tsx"* ]]
}

# --- Impact detection ---

@test "finds tests that import the modified module" {
    mkdir -p "${PROJECT_DIR}/src/services" "${PROJECT_DIR}/tests"
    echo "class UserService:" > "${PROJECT_DIR}/src/services/users.py"
    echo "from services.users import UserService" > "${PROJECT_DIR}/tests/test_users.py"
    echo "from services.users import UserService" > "${PROJECT_DIR}/tests/test_integration.py"
    run_hook "$HOOK" cwd="$PROJECT_DIR" session_id="$SESSION_ID" file_path="${PROJECT_DIR}/src/services/users.py"
    assert_success
    local impact
    impact=$(get_impact)
    [[ "$impact" == *"test_users.py"* ]]
    [[ "$impact" == *"test_integration.py"* ]]
}

@test "deduplicates impact entries across multiple edits" {
    mkdir -p "${PROJECT_DIR}/src" "${PROJECT_DIR}/tests"
    echo "code" > "${PROJECT_DIR}/src/auth.py"
    echo "import auth" > "${PROJECT_DIR}/tests/test_auth.py"
    # Edit the file twice
    run_hook "$HOOK" cwd="$PROJECT_DIR" session_id="$SESSION_ID" file_path="${PROJECT_DIR}/src/auth.py"
    run_hook "$HOOK" cwd="$PROJECT_DIR" session_id="$SESSION_ID" file_path="${PROJECT_DIR}/src/auth.py"
    assert_success
    local line_count
    line_count=$(wc -l < "${PROJECT_DIR}/.sentinel/sessions/${SHORT_ID}/impact-tests.txt" | tr -d ' ')
    [ "$line_count" -eq 1 ]
}

@test "no impact file created when no tests reference the module" {
    mkdir -p "${PROJECT_DIR}/src" "${PROJECT_DIR}/tests"
    echo "code" > "${PROJECT_DIR}/src/isolated.py"
    echo "import something_else" > "${PROJECT_DIR}/tests/test_other.py"
    run_hook "$HOOK" cwd="$PROJECT_DIR" session_id="$SESSION_ID" file_path="${PROJECT_DIR}/src/isolated.py"
    assert_success
    # impact-tests.txt should not exist or be empty
    local impact
    impact=$(get_impact)
    [ -z "$impact" ]
}

@test "exits gracefully with empty file path" {
    run_hook "$HOOK" cwd="$PROJECT_DIR" session_id="$SESSION_ID" file_path=""
    assert_success
}

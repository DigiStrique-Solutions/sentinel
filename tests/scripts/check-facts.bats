#!/usr/bin/env bats

load "${BATS_TEST_DIRNAME}/../helpers/common"

SCRIPT="${SENTINEL_ROOT}/scripts/check-facts.sh"

setup() {
    export PROJECT_DIR="${BATS_TEST_TMPDIR}/project"
    mkdir -p "$PROJECT_DIR"
}

# --- Graceful exits ---

@test "exits when no CLAUDE.md" {
    run bash "$SCRIPT" "$PROJECT_DIR"
    assert_success
    assert_output ""
}

@test "exits when no config file" {
    echo "# Project" > "${PROJECT_DIR}/CLAUDE.md"
    run bash "$SCRIPT" "$PROJECT_DIR"
    assert_success
    assert_output ""
}

# --- Fact checking ---

@test "detects count mismatch greater than 10 percent" {
    cat > "${PROJECT_DIR}/CLAUDE.md" <<'EOF'
# Project
We have 100 API endpoints serving traffic.
EOF
    # Create 50 files (50% of claimed 100 — well over 10% threshold)
    mkdir -p "${PROJECT_DIR}/src"
    for i in $(seq 1 50); do
        echo "endpoint" > "${PROJECT_DIR}/src/endpoint${i}.py"
    done
    create_fact_checks "$PROJECT_DIR" "checks:
  - description: API endpoints
    pattern: '[0-9]+ API endpoints'
    command: \"find src/ -name '*.py' -type f | wc -l\""
    run bash "$SCRIPT" "$PROJECT_DIR"
    assert_success
    assert_output --partial "FACT CHECK"
    assert_output --partial "API endpoints"
}

@test "passes when count within 10 percent" {
    cat > "${PROJECT_DIR}/CLAUDE.md" <<'EOF'
# Project
We have 10 models in the system.
EOF
    mkdir -p "${PROJECT_DIR}/src/models"
    for i in $(seq 1 10); do
        echo "model" > "${PROJECT_DIR}/src/models/model${i}.py"
    done
    create_fact_checks "$PROJECT_DIR" "checks:
  - description: Models
    pattern: '[0-9]+ models'
    command: \"find src/models/ -name '*.py' -type f | wc -l\""
    run bash "$SCRIPT" "$PROJECT_DIR"
    assert_success
    assert_output ""
}

@test "handles claimed zero gracefully" {
    cat > "${PROJECT_DIR}/CLAUDE.md" <<'EOF'
# Project
We have 0 known bugs.
EOF
    create_fact_checks "$PROJECT_DIR" "checks:
  - description: Known bugs
    pattern: '[0-9]+ known bugs'
    command: \"echo 5\""
    run bash "$SCRIPT" "$PROJECT_DIR"
    assert_success
    # claimed=0 should be skipped
    assert_output ""
}

@test "handles actual zero gracefully" {
    cat > "${PROJECT_DIR}/CLAUDE.md" <<'EOF'
# Project
We have 10 test files.
EOF
    create_fact_checks "$PROJECT_DIR" "checks:
  - description: Test files
    pattern: '[0-9]+ test files'
    command: \"echo 0\""
    run bash "$SCRIPT" "$PROJECT_DIR"
    assert_success
    # actual=0 should be skipped
    assert_output ""
}

@test "multiple checks in one config" {
    cat > "${PROJECT_DIR}/CLAUDE.md" <<'EOF'
# Project
We have 10 controllers and 20 models.
EOF
    mkdir -p "${PROJECT_DIR}/src/controllers" "${PROJECT_DIR}/src/models"
    for i in $(seq 1 10); do
        echo "ctrl" > "${PROJECT_DIR}/src/controllers/ctrl${i}.py"
    done
    for i in $(seq 1 20); do
        echo "model" > "${PROJECT_DIR}/src/models/model${i}.py"
    done
    create_fact_checks "$PROJECT_DIR" "checks:
  - description: Controllers
    pattern: '[0-9]+ controllers'
    command: \"find src/controllers/ -name '*.py' -type f | wc -l\"
  - description: Models
    pattern: '[0-9]+ models'
    command: \"find src/models/ -name '*.py' -type f | wc -l\""
    run bash "$SCRIPT" "$PROJECT_DIR"
    assert_success
    # Both are accurate — no warnings
    assert_output ""
}

@test "threshold minimum of 1 for small numbers" {
    cat > "${PROJECT_DIR}/CLAUDE.md" <<'EOF'
# Project
We have 3 services.
EOF
    # 3 claimed, 5 actual → diff=2, threshold=max(3/10,1)=1 → 2>1 → warn
    create_fact_checks "$PROJECT_DIR" "checks:
  - description: Services
    pattern: '[0-9]+ services'
    command: \"echo 5\""
    run bash "$SCRIPT" "$PROJECT_DIR"
    assert_success
    assert_output --partial "Services"
    assert_output --partial "says 3"
    assert_output --partial "actual is 5"
}

@test "last check processed at EOF" {
    cat > "${PROJECT_DIR}/CLAUDE.md" <<'EOF'
We have 100 tools available.
EOF
    create_fact_checks "$PROJECT_DIR" "checks:
  - description: Tools
    pattern: '[0-9]+ tools'
    command: \"echo 50\""
    # No trailing newline — EOF triggers process_check
    run bash "$SCRIPT" "$PROJECT_DIR"
    assert_success
    assert_output --partial "Tools"
}

@test "parses YAML with single-quoted values" {
    cat > "${PROJECT_DIR}/CLAUDE.md" <<'EOF'
We have 10 endpoints.
EOF
    mkdir -p "${PROJECT_DIR}/src"
    for i in $(seq 1 10); do echo "x" > "${PROJECT_DIR}/src/ep${i}.py"; done
    create_fact_checks "$PROJECT_DIR" "checks:
  - description: 'Endpoints'
    pattern: '[0-9]+ endpoints'
    command: 'find src/ -name \"*.py\" -type f | wc -l'"
    run bash "$SCRIPT" "$PROJECT_DIR"
    assert_success
    assert_output ""
}

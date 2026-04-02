#!/usr/bin/env bats

load "${BATS_TEST_DIRNAME}/../helpers/common"

SCRIPT="${SENTINEL_ROOT}/scripts/detect-drift.sh"

setup() {
    export PROJECT_DIR="${BATS_TEST_TMPDIR}/project"
    mkdir -p "$PROJECT_DIR"
    mkdir -p "${PROJECT_DIR}/vault/architecture"
}

# --- Graceful exits ---

@test "exits when no architecture dir" {
    rm -rf "${PROJECT_DIR}/vault/architecture"
    run bash "$SCRIPT" "$PROJECT_DIR"
    assert_success
    assert_output ""
}

@test "exits when architecture dir is empty" {
    run bash "$SCRIPT" "$PROJECT_DIR"
    assert_success
    assert_output ""
}

# --- Dead reference detection ---

@test "detects dead file references" {
    cat > "${PROJECT_DIR}/vault/architecture/overview.md" <<'EOF'
# System Overview

The main entry point is src/main.py which handles all requests.
Tests are in tests/test_main.py.
EOF
    # Neither file exists
    run bash "$SCRIPT" "$PROJECT_DIR"
    assert_success
    assert_output --partial "src/main.py"
}

@test "passes when all references alive" {
    mkdir -p "${PROJECT_DIR}/src"
    echo "code" > "${PROJECT_DIR}/src/main.py"
    cat > "${PROJECT_DIR}/vault/architecture/overview.md" <<'EOF'
# System Overview

The main entry point is src/main.py.
EOF
    run bash "$SCRIPT" "$PROJECT_DIR"
    assert_success
    assert_output ""
}

@test "mixed dead and alive refs — only dead ones reported" {
    mkdir -p "${PROJECT_DIR}/src"
    echo "code" > "${PROJECT_DIR}/src/main.py"
    cat > "${PROJECT_DIR}/vault/architecture/overview.md" <<'EOF'
# System Overview

Entry point: src/main.py (exists)
Config: src/config.py (deleted)
EOF
    run bash "$SCRIPT" "$PROJECT_DIR"
    assert_success
    assert_output --partial "src/config.py"
    refute_output --partial "src/main.py"
}

@test "doc with no code references is skipped" {
    cat > "${PROJECT_DIR}/vault/architecture/principles.md" <<'EOF'
# Architecture Principles

We follow clean architecture with separation of concerns.
No file paths here, just prose.
EOF
    run bash "$SCRIPT" "$PROJECT_DIR"
    assert_success
    assert_output ""
}

@test "multiple architecture docs processed independently" {
    cat > "${PROJECT_DIR}/vault/architecture/api.md" <<'EOF'
# API Layer
Main handler: src/api/handler.py
EOF
    cat > "${PROJECT_DIR}/vault/architecture/db.md" <<'EOF'
# Database Layer
Models: src/models/user.py
EOF
    # Neither exists
    run bash "$SCRIPT" "$PROJECT_DIR"
    assert_success
    assert_output --partial "src/api/handler.py"
    assert_output --partial "src/models/user.py"
}

@test "extracts various file extensions" {
    cat > "${PROJECT_DIR}/vault/architecture/frontend.md" <<'EOF'
# Frontend

Components in src/components/App.tsx and tests/App.spec.tsx.
Styles in src/styles/main.css.
EOF
    run bash "$SCRIPT" "$PROJECT_DIR"
    assert_success
    assert_output --partial "src/components/App.tsx"
}

# --- Modified area detection ---

@test "detects modified areas with modified files list" {
    mkdir -p "${PROJECT_DIR}/src/auth"
    echo "code" > "${PROJECT_DIR}/src/auth/login.py"
    cat > "${PROJECT_DIR}/vault/architecture/auth.md" <<'EOF'
# Auth System
All auth logic in src/auth/ directory.
EOF
    # Create a modified files list
    local modified_file="${BATS_TEST_TMPDIR}/modified.txt"
    echo "src/auth/login.py" > "$modified_file"
    run bash "$SCRIPT" "$PROJECT_DIR" "$modified_file"
    assert_success
    # Should detect the area was modified (even though files exist)
    assert_output --partial "auth"
}

@test "handles no modified files gracefully" {
    mkdir -p "${PROJECT_DIR}/src"
    echo "code" > "${PROJECT_DIR}/src/app.py"
    cat > "${PROJECT_DIR}/vault/architecture/overview.md" <<'EOF'
# Overview
Main app: src/app.py
EOF
    # No modified files arg
    run bash "$SCRIPT" "$PROJECT_DIR"
    assert_success
    assert_output ""
}

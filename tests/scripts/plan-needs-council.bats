#!/usr/bin/env bats

load "${BATS_TEST_DIRNAME}/../helpers/common"

SCRIPT="${SENTINEL_ROOT}/scripts/plan-needs-council.sh"

setup() {
    export PROJECT_DIR="${BATS_TEST_TMPDIR}/project"
    mkdir -p "$PROJECT_DIR"
}

# Helper: write a plan with N files and an optional Council flag value
make_plan() {
    local file="$1"
    local n="$2"
    local council_flag="${3:-}"

    {
        echo "# Test Plan"
        echo
        if [ -n "$council_flag" ]; then
            echo "**Council required:** $council_flag"
            echo
        fi
        echo "## File Layout"
        echo "| File | New/Modified |"
        echo "|---|---|"
        for i in $(seq 1 "$n"); do
            echo "| \`src/file_${i}.py\` | New |"
        done
    } > "$file"
}

# --- Argument validation ---

@test "fails with exit 2 when plan_path is missing" {
    run bash "$SCRIPT"
    [ "$status" -eq 2 ]
    [[ "$output" == *"plan_path required"* ]]
}

@test "fails with exit 2 when plan file does not exist" {
    run bash "$SCRIPT" "/nonexistent/plan.md"
    [ "$status" -eq 2 ]
    [[ "$output" == *"not found"* ]]
}

# --- Auto-trigger by file count ---

@test "small plan (2 files, no flag) does NOT need council" {
    make_plan "${PROJECT_DIR}/plan.md" 2
    run bash "$SCRIPT" "${PROJECT_DIR}/plan.md"
    [ "$status" -eq 1 ]
    echo "$output" | jq -e '.needed == false'
    echo "$output" | jq -e '.file_count == 2'
    echo "$output" | jq -e '.explicit_flag == "absent"'
    echo "$output" | jq -e '.reasons | contains(["file_count_below_threshold"])'
}

@test "exactly threshold (5 files) does NOT need council (>, not >=)" {
    make_plan "${PROJECT_DIR}/plan.md" 5
    run bash "$SCRIPT" "${PROJECT_DIR}/plan.md"
    [ "$status" -eq 1 ]
    echo "$output" | jq -e '.needed == false'
    echo "$output" | jq -e '.file_count == 5'
}

@test "above threshold (6 files) DOES need council" {
    make_plan "${PROJECT_DIR}/plan.md" 6
    run bash "$SCRIPT" "${PROJECT_DIR}/plan.md"
    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.needed == true'
    echo "$output" | jq -e '.file_count == 6'
    echo "$output" | jq -e '.reasons | contains(["file_count_above_threshold"])'
}

@test "well above threshold (10 files) DOES need council" {
    make_plan "${PROJECT_DIR}/plan.md" 10
    run bash "$SCRIPT" "${PROJECT_DIR}/plan.md"
    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.needed == true'
    echo "$output" | jq -e '.file_count == 10'
}

# --- Explicit flag handling ---

@test "explicit Council required: true overrides small plan" {
    make_plan "${PROJECT_DIR}/plan.md" 1 "true"
    run bash "$SCRIPT" "${PROJECT_DIR}/plan.md"
    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.needed == true'
    echo "$output" | jq -e '.explicit_flag == "true"'
    echo "$output" | jq -e '.reasons | contains(["explicit_flag"])'
}

@test "explicit Council required: false overrides big plan" {
    make_plan "${PROJECT_DIR}/plan.md" 20 "false"
    run bash "$SCRIPT" "${PROJECT_DIR}/plan.md"
    [ "$status" -eq 1 ]
    echo "$output" | jq -e '.needed == false'
    echo "$output" | jq -e '.explicit_flag == "false"'
    echo "$output" | jq -e '.reasons | contains(["explicit_override_skip"])'
}

@test "yes is accepted as true" {
    make_plan "${PROJECT_DIR}/plan.md" 1 "yes"
    run bash "$SCRIPT" "${PROJECT_DIR}/plan.md"
    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.explicit_flag == "true"'
}

@test "no is accepted as false" {
    make_plan "${PROJECT_DIR}/plan.md" 20 "no"
    run bash "$SCRIPT" "${PROJECT_DIR}/plan.md"
    [ "$status" -eq 1 ]
    echo "$output" | jq -e '.explicit_flag == "false"'
}

@test "case-insensitive flag values" {
    make_plan "${PROJECT_DIR}/plan.md" 1 "TRUE"
    run bash "$SCRIPT" "${PROJECT_DIR}/plan.md"
    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.explicit_flag == "true"'
}

# --- Custom threshold ---

@test "custom threshold of 2 fires on 3 files" {
    make_plan "${PROJECT_DIR}/plan.md" 3
    run bash "$SCRIPT" "${PROJECT_DIR}/plan.md" 2
    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.threshold == 2'
    echo "$output" | jq -e '.needed == true'
}

@test "custom threshold of 100 does not fire on 7 files" {
    make_plan "${PROJECT_DIR}/plan.md" 7
    run bash "$SCRIPT" "${PROJECT_DIR}/plan.md" 100
    [ "$status" -eq 1 ]
    echo "$output" | jq -e '.needed == false'
}

# --- File path detection across formats ---

@test "counts files in 'Create:' bullets format" {
    cat > "${PROJECT_DIR}/plan.md" <<'EOF'
# Plan

## Files
- Create: `src/a.py`
- Create: `src/b.py`
- Create: `src/c.py`
- Modify: `src/d.py`
- Modify: `src/e.py`
- Test: `tests/test_a.py`
- Test: `tests/test_b.py`
EOF
    run bash "$SCRIPT" "${PROJECT_DIR}/plan.md"
    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.file_count == 7'
}

@test "counts files in markdown table format" {
    cat > "${PROJECT_DIR}/plan.md" <<'EOF'
# Plan

| File | New/Modified |
|---|---|
| `src/a.py` | New |
| `src/b.ts` | New |
| `src/c.tsx` | New |
| `src/d.go` | Modify |
| `src/e.rs` | New |
| `tests/test_a.py` | New |
EOF
    run bash "$SCRIPT" "${PROJECT_DIR}/plan.md"
    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.file_count == 6'
}

@test "deduplicates the same file mentioned twice" {
    cat > "${PROJECT_DIR}/plan.md" <<'EOF'
# Plan

## Files
- Create: `src/a.py`
- Create: `src/a.py`
- Modify: `src/a.py`
EOF
    run bash "$SCRIPT" "${PROJECT_DIR}/plan.md"
    [ "$status" -eq 1 ]
    echo "$output" | jq -e '.file_count == 1'
}

@test "ignores backticked code that is not a file path" {
    cat > "${PROJECT_DIR}/plan.md" <<'EOF'
# Plan

## Notes
- The function `parse_input` should call `validate_user`.
- `npm install` will need updating.

## Files
- Create: `src/foo.py`
EOF
    run bash "$SCRIPT" "${PROJECT_DIR}/plan.md"
    [ "$status" -eq 1 ]
    echo "$output" | jq -e '.file_count == 1'
}

# --- JSON output shape ---

@test "outputs valid JSON" {
    make_plan "${PROJECT_DIR}/plan.md" 3
    run bash "$SCRIPT" "${PROJECT_DIR}/plan.md"
    echo "$output" | jq . >/dev/null
}

@test "JSON includes plan_path, needed, reasons, file_count, threshold, explicit_flag" {
    make_plan "${PROJECT_DIR}/plan.md" 3
    run bash "$SCRIPT" "${PROJECT_DIR}/plan.md"
    echo "$output" | jq -e '
        has("plan_path") and has("needed") and has("reasons")
        and has("file_count") and has("threshold") and has("explicit_flag")
    '
}

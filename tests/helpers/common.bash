#!/usr/bin/env bash
# Common test helper for Sentinel BATS tests
#
# Provides shared setup functions, JSON builders, and utilities
# used across all test files.

# Load BATS libraries
load "${BATS_TEST_DIRNAME}/../test_helper/bats-support/load"
load "${BATS_TEST_DIRNAME}/../test_helper/bats-assert/load"
load "${BATS_TEST_DIRNAME}/../test_helper/bats-file/load"

# Project root (sentinel plugin directory)
SENTINEL_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"

# --- Scaffold Functions ---

# Create a minimal vault directory structure
create_test_vault() {
    local base="${1:-${BATS_TEST_TMPDIR}}"
    mkdir -p "${base}/vault/investigations/resolved"
    mkdir -p "${base}/vault/gotchas"
    mkdir -p "${base}/vault/decisions"
    mkdir -p "${base}/vault/workflows"
    mkdir -p "${base}/vault/quality"
    mkdir -p "${base}/vault/patterns/learned"
    mkdir -p "${base}/vault/architecture"
    mkdir -p "${base}/vault/changelog"
    mkdir -p "${base}/vault/session-recovery"
    mkdir -p "${base}/vault/activity"
    mkdir -p "${base}/vault/completed"
    echo "${base}/vault"
}

# Create .sentinel/ tracking directory
create_test_sentinel() {
    local base="${1:-${BATS_TEST_TMPDIR}}"
    local session_id="${2:-test-session-123}"
    local short_id="${session_id:0:12}"
    mkdir -p "${base}/.sentinel/sessions/${short_id}"
    echo "${base}/.sentinel"
}

# Initialize a test git repo with an initial commit
init_test_git_repo() {
    local base="${1:-${BATS_TEST_TMPDIR}}"
    cd "$base"
    git init -q
    git config user.name "Test User"
    git config user.email "test@example.com"
    echo "initial" > README.md
    git add README.md
    git commit -q -m "initial commit"
    cd - > /dev/null
}

# --- JSON Input Builders ---

# Build the standard hook input JSON
# Usage: create_hook_input [key=value ...]
# Example: create_hook_input cwd=/tmp session_id=abc-123
create_hook_input() {
    local cwd=""
    local session_id=""
    local stop_hook_active="false"
    local transcript_path=""
    local tool_name=""
    local tool_input_command=""
    local tool_input_file_path=""
    local tool_output_exit_code=""
    local tool_output_stdout=""
    local tool_output_stderr=""
    local prompt=""

    for arg in "$@"; do
        local key="${arg%%=*}"
        local val="${arg#*=}"
        case "$key" in
            cwd) cwd="$val" ;;
            session_id) session_id="$val" ;;
            stop_hook_active) stop_hook_active="$val" ;;
            transcript_path) transcript_path="$val" ;;
            tool_name) tool_name="$val" ;;
            command) tool_input_command="$val" ;;
            file_path) tool_input_file_path="$val" ;;
            exit_code) tool_output_exit_code="$val" ;;
            stdout) tool_output_stdout="$val" ;;
            stderr) tool_output_stderr="$val" ;;
            prompt) prompt="$val" ;;
        esac
    done

    # Build JSON with jq for safety
    local json="{}"
    [ -n "$cwd" ] && json=$(echo "$json" | jq --arg v "$cwd" '. + {cwd: $v}')
    [ -n "$session_id" ] && json=$(echo "$json" | jq --arg v "$session_id" '. + {session_id: $v}')
    [ "$stop_hook_active" = "true" ] && json=$(echo "$json" | jq '. + {stop_hook_active: true}')
    [ -n "$transcript_path" ] && json=$(echo "$json" | jq --arg v "$transcript_path" '. + {transcript_path: $v}')
    [ -n "$prompt" ] && json=$(echo "$json" | jq --arg v "$prompt" '. + {prompt: $v}')

    # Tool input
    if [ -n "$tool_input_command" ] || [ -n "$tool_input_file_path" ]; then
        local ti="{}"
        [ -n "$tool_input_command" ] && ti=$(echo "$ti" | jq --arg v "$tool_input_command" '. + {command: $v}')
        [ -n "$tool_input_file_path" ] && ti=$(echo "$ti" | jq --arg v "$tool_input_file_path" '. + {file_path: $v}')
        json=$(echo "$json" | jq --argjson ti "$ti" '. + {tool_input: $ti}')
    fi

    # Tool output
    if [ -n "$tool_output_exit_code" ] || [ -n "$tool_output_stdout" ] || [ -n "$tool_output_stderr" ]; then
        local to="{}"
        [ -n "$tool_output_exit_code" ] && to=$(echo "$to" | jq --arg v "$tool_output_exit_code" '. + {exit_code: $v}')
        [ -n "$tool_output_stdout" ] && to=$(echo "$to" | jq --arg v "$tool_output_stdout" '. + {stdout: $v}')
        [ -n "$tool_output_stderr" ] && to=$(echo "$to" | jq --arg v "$tool_output_stderr" '. + {stderr: $v}')
        json=$(echo "$json" | jq --argjson to "$to" '. + {tool_output: $to}')
    fi

    echo "$json"
}

# --- Hook Runner ---

# Run a hook script with JSON piped to stdin
# Usage: run_hook <script_path> [key=value ...]
run_hook() {
    local script="$1"
    shift
    local input
    input=$(create_hook_input "$@")
    run bash -c "echo '$input' | bash '$script'"
}

# --- Test Data Creators ---

# Create an investigation file
# Usage: create_investigation <vault_dir> <filename> [status]
create_investigation() {
    local vault_dir="$1"
    local filename="$2"
    local status="${3:-open}"
    cat > "${vault_dir}/investigations/${filename}" <<EOF
---
date: 2026-04-01
status: ${status}
area: test
---

# Test Investigation

This is a test investigation.
EOF
}

# Create a gotcha file
# Usage: create_gotcha <vault_dir> <filename> <heading> [content]
create_gotcha() {
    local vault_dir="$1"
    local filename="$2"
    local heading="$3"
    local content="${4:-This is a known pitfall.}"
    cat > "${vault_dir}/gotchas/${filename}" <<EOF
# ${heading}

${content}
EOF
}

# Create a learned pattern file
# Usage: create_pattern <vault_dir> <filename> <confidence>
create_pattern() {
    local vault_dir="$1"
    local filename="$2"
    local confidence="$3"
    cat > "${vault_dir}/patterns/learned/${filename}" <<EOF
confidence: ${confidence}
observations: 5

# Test Pattern

A reusable pattern.
EOF
}

# Create a session recovery file with specific mtime
# Usage: create_recovery <vault_dir> <filename> [minutes_ago]
create_recovery() {
    local vault_dir="$1"
    local filename="$2"
    local minutes_ago="${3:-30}"
    cat > "${vault_dir}/session-recovery/${filename}" <<EOF
---
type: session-recovery
status: active
---

# Session Recovery

Context from previous session.
EOF
    # Set modification time
    if [[ "$OSTYPE" == "darwin"* ]]; then
        touch -t "$(date -v-${minutes_ago}M +%Y%m%d%H%M.%S)" "${vault_dir}/session-recovery/${filename}"
    else
        touch -d "${minutes_ago} minutes ago" "${vault_dir}/session-recovery/${filename}"
    fi
}

# Create an activity file
# Usage: create_activity <vault_dir> <date> <entries>
create_activity() {
    local vault_dir="$1"
    local date="$2"
    local entries="$3"
    cat > "${vault_dir}/activity/${date}.md" <<EOF
# Activity — ${date}

${entries}
EOF
}

# Create an evidence log
# Usage: create_evidence_log <sentinel_dir> <session_short_id> <entries>
create_evidence_log() {
    local sentinel_dir="$1"
    local short_id="$2"
    local entries="$3"
    mkdir -p "${sentinel_dir}/sessions/${short_id}"
    echo "$entries" > "${sentinel_dir}/sessions/${short_id}/evidence.log"
}

# Create a todos.json file
# Usage: create_todos_json <sentinel_dir> <session_short_id> <json_content>
create_todos_json() {
    local sentinel_dir="$1"
    local short_id="$2"
    local json_content="$3"
    mkdir -p "${sentinel_dir}/sessions/${short_id}"
    echo "$json_content" > "${sentinel_dir}/sessions/${short_id}/todos.json"
}

# Create a modified-files.txt
# Usage: create_modified_files <sentinel_dir> <session_short_id> <file_list>
create_modified_files() {
    local sentinel_dir="$1"
    local short_id="$2"
    local file_list="$3"
    mkdir -p "${sentinel_dir}/sessions/${short_id}"
    echo "$file_list" > "${sentinel_dir}/sessions/${short_id}/modified-files.txt"
}

# Set file age in days (cross-platform)
# Usage: set_file_age <file> <days>
set_file_age() {
    local file="$1"
    local days="$2"
    if [[ "$OSTYPE" == "darwin"* ]]; then
        touch -t "$(date -v-${days}d +%Y%m%d%H%M.%S)" "$file"
    else
        touch -d "${days} days ago" "$file"
    fi
}

# Create a fact-checks.yml config
# Usage: create_fact_checks <project_root> <yaml_content>
create_fact_checks() {
    local project_root="$1"
    local yaml_content="$2"
    mkdir -p "${project_root}/.sentinel"
    echo "$yaml_content" > "${project_root}/.sentinel/fact-checks.yml"
}

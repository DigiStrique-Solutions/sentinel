#!/bin/bash
# workflow-state.sh — State management for Sentinel workflows.
#
# Single source of truth for reading/writing workflow run state. Called by
# the workflow-runner skill, the /sentinel-workflow command, and lifecycle
# hooks. All state operations go through this script.
#
# Usage:
#   workflow-state.sh start <workflow-name>
#       Creates a new run directory, emits workflow_started event, prints run-id.
#
#   workflow-state.sh step-start <run-id> <step-num> <step-name>
#       Emits step_started event, updates state.md current_step.
#
#   workflow-state.sh step-complete <run-id> <step-num> [artifact-path]
#       Emits step_completed event, marks step done.
#
#   workflow-state.sh step-fail <run-id> <step-num> <reason>
#       Emits step_failed event.
#
#   workflow-state.sh finish <run-id> <status>
#       Emits workflow_finished event, archives run to completed/ or abandoned/.
#       Status: completed | aborted
#
#   workflow-state.sh find-active [workflow-name]
#       Prints run-id of active run for workflow-name (or newest active run if
#       name omitted). Empty output if none.
#
#   workflow-state.sh list
#       Lists all runs (active, completed, abandoned) with status and last event.
#
#   workflow-state.sh status <run-id>
#       Prints state.md + last few events for a run.
#
# Exit codes: 0 on success, 1 on user error, 2 on internal error.

set -uo pipefail

# -----------------------------------------------------------------------------
# Setup
# -----------------------------------------------------------------------------

# Detect vault root. Prefer VAULT_ROOT env var (set by caller), fall back to
# ./vault (if running from project root), then fail.
detect_vault_root() {
  if [ -n "${VAULT_ROOT:-}" ] && [ -d "$VAULT_ROOT" ]; then
    echo "$VAULT_ROOT"
    return 0
  fi
  if [ -d "./vault" ]; then
    echo "$(pwd)/vault"
    return 0
  fi
  if [ -d "../vault" ]; then
    echo "$(cd .. && pwd)/vault"
    return 0
  fi
  # Walk up to find a vault
  local dir="$(pwd)"
  while [ "$dir" != "/" ]; do
    if [ -d "$dir/vault" ]; then
      echo "$dir/vault"
      return 0
    fi
    dir="$(dirname "$dir")"
  done
  echo "ERROR: no vault directory found (set VAULT_ROOT or run from a project with vault/)" >&2
  return 2
}

VAULT_ROOT="$(detect_vault_root)" || exit 2
RUNS_DIR="$VAULT_ROOT/workflows/runs"
mkdir -p "$RUNS_DIR" "$RUNS_DIR/completed" "$RUNS_DIR/abandoned"

# ISO 8601 timestamp, UTC
iso_ts() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

# Append a JSON event to a run's events.jsonl.
# Usage: append_event <run-dir> <event-json>
append_event() {
  local run_dir="$1"
  local event="$2"
  echo "$event" >> "$run_dir/events.jsonl"
}

# Build a JSON event object. Uses jq if available, falls back to printf.
# Usage: build_event <event-name> [k1 v1 k2 v2 ...]
build_event() {
  local event_name="$1"
  shift
  local ts
  ts="$(iso_ts)"

  if command -v jq >/dev/null 2>&1; then
    local jq_args=()
    jq_args+=(--arg ts "$ts" --arg event "$event_name")
    local fields='"ts": $ts, "event": $event'
    while [ $# -ge 2 ]; do
      local k="$1"; local v="$2"
      jq_args+=(--arg "$k" "$v")
      fields="$fields, \"$k\": \$$k"
      shift 2
    done
    jq -nc "${jq_args[@]}" "{$fields}"
  else
    # Naive fallback — escapes double quotes in values only.
    local out="{\"ts\":\"$ts\",\"event\":\"$event_name\""
    while [ $# -ge 2 ]; do
      local k="$1"
      local v="${2//\"/\\\"}"
      out="$out,\"$k\":\"$v\""
      shift 2
    done
    out="$out}"
    echo "$out"
  fi
}

# -----------------------------------------------------------------------------
# Commands
# -----------------------------------------------------------------------------

cmd_start() {
  local workflow="${1:-}"
  if [ -z "$workflow" ]; then
    echo "usage: workflow-state.sh start <workflow-name>" >&2
    return 1
  fi

  local timestamp
  timestamp="$(date -u +"%Y-%m-%d-%H%M%S")"
  local run_id="${workflow}-${timestamp}"
  local run_dir="$RUNS_DIR/$run_id"

  if [ -d "$run_dir" ]; then
    echo "ERROR: run directory already exists: $run_dir" >&2
    return 2
  fi

  mkdir -p "$run_dir/artifacts"

  cat > "$run_dir/state.md" <<EOF
---
workflow: $workflow
run_id: $run_id
started: $(iso_ts)
status: in-progress
current_step: 0
---

# Workflow run: $run_id

Workflow: **$workflow**
Started: $(iso_ts)
Status: in-progress

## Steps

_No steps started yet. The first step will be recorded here._
EOF

  touch "$run_dir/events.jsonl"
  append_event "$run_dir" "$(build_event workflow_started workflow "$workflow" run_id "$run_id")"

  echo "$run_id"
}

cmd_step_start() {
  local run_id="${1:-}"
  local step_num="${2:-}"
  local step_name="${3:-}"

  if [ -z "$run_id" ] || [ -z "$step_num" ] || [ -z "$step_name" ]; then
    echo "usage: workflow-state.sh step-start <run-id> <step-num> <step-name>" >&2
    return 1
  fi

  local run_dir="$RUNS_DIR/$run_id"
  if [ ! -d "$run_dir" ]; then
    echo "ERROR: run not found: $run_id" >&2
    return 2
  fi

  append_event "$run_dir" "$(build_event step_started run_id "$run_id" step "$step_num" name "$step_name")"

  # Update state.md — swap the current_step frontmatter field.
  local tmp
  tmp="$(mktemp)"
  awk -v step="$step_num" '
    /^current_step: / { print "current_step: " step; next }
    { print }
  ' "$run_dir/state.md" > "$tmp"
  mv "$tmp" "$run_dir/state.md"

  # Append a step section to the body if it doesn't exist.
  if ! grep -q "^## Step $step_num: " "$run_dir/state.md"; then
    cat >> "$run_dir/state.md" <<EOF

## Step $step_num: $step_name

Status: in-progress
Started: $(iso_ts)
EOF
  fi
}

cmd_step_complete() {
  local run_id="${1:-}"
  local step_num="${2:-}"
  local artifact="${3:-}"

  if [ -z "$run_id" ] || [ -z "$step_num" ]; then
    echo "usage: workflow-state.sh step-complete <run-id> <step-num> [artifact-path]" >&2
    return 1
  fi

  local run_dir="$RUNS_DIR/$run_id"
  if [ ! -d "$run_dir" ]; then
    echo "ERROR: run not found: $run_id" >&2
    return 2
  fi

  if [ -n "$artifact" ]; then
    append_event "$run_dir" "$(build_event step_completed run_id "$run_id" step "$step_num" artifact "$artifact")"
  else
    append_event "$run_dir" "$(build_event step_completed run_id "$run_id" step "$step_num")"
  fi

  # Append completion note to the step section.
  cat >> "$run_dir/state.md" <<EOF

**Completed:** $(iso_ts)${artifact:+
**Artifact:** \`$artifact\`}
EOF
}

cmd_step_fail() {
  local run_id="${1:-}"
  local step_num="${2:-}"
  local reason="${3:-}"

  if [ -z "$run_id" ] || [ -z "$step_num" ]; then
    echo "usage: workflow-state.sh step-fail <run-id> <step-num> <reason>" >&2
    return 1
  fi

  local run_dir="$RUNS_DIR/$run_id"
  if [ ! -d "$run_dir" ]; then
    echo "ERROR: run not found: $run_id" >&2
    return 2
  fi

  append_event "$run_dir" "$(build_event step_failed run_id "$run_id" step "$step_num" reason "$reason")"

  cat >> "$run_dir/state.md" <<EOF

**Failed:** $(iso_ts)
**Reason:** $reason
EOF
}

cmd_finish() {
  local run_id="${1:-}"
  local status="${2:-completed}"

  if [ -z "$run_id" ]; then
    echo "usage: workflow-state.sh finish <run-id> <status>" >&2
    return 1
  fi

  local run_dir="$RUNS_DIR/$run_id"
  if [ ! -d "$run_dir" ]; then
    echo "ERROR: run not found: $run_id" >&2
    return 2
  fi

  append_event "$run_dir" "$(build_event workflow_finished run_id "$run_id" status "$status")"

  # Update state.md frontmatter status
  local tmp
  tmp="$(mktemp)"
  awk -v status="$status" '
    /^status: / { print "status: " status; next }
    { print }
  ' "$run_dir/state.md" > "$tmp"
  mv "$tmp" "$run_dir/state.md"

  # Move to archive
  local archive_dir
  case "$status" in
    completed) archive_dir="$RUNS_DIR/completed" ;;
    aborted)   archive_dir="$RUNS_DIR/abandoned" ;;
    *)         archive_dir="$RUNS_DIR/completed" ;;
  esac

  mv "$run_dir" "$archive_dir/$run_id"
}

cmd_find_active() {
  local workflow="${1:-}"

  # Look through non-archive subdirs only
  local newest=""
  local newest_ts=0
  for d in "$RUNS_DIR"/*/; do
    [ -d "$d" ] || continue
    local base
    base="$(basename "$d")"
    [ "$base" = "completed" ] && continue
    [ "$base" = "abandoned" ] && continue

    # Check status in frontmatter
    local status
    status="$(grep '^status: ' "$d/state.md" 2>/dev/null | head -1 | sed 's/^status: //')"
    [ "$status" = "in-progress" ] || continue

    # Filter by workflow name if given
    if [ -n "$workflow" ]; then
      local wf
      wf="$(grep '^workflow: ' "$d/state.md" 2>/dev/null | head -1 | sed 's/^workflow: //')"
      [ "$wf" = "$workflow" ] || continue
    fi

    # Keep track of newest by mtime
    local mtime
    mtime="$(stat -f %m "$d" 2>/dev/null || stat -c %Y "$d" 2>/dev/null)"
    if [ "${mtime:-0}" -gt "$newest_ts" ]; then
      newest_ts="$mtime"
      newest="$base"
    fi
  done

  echo "$newest"
}

cmd_list() {
  echo "Workflow runs in $RUNS_DIR"
  echo "===================================================="

  echo ""
  echo "IN PROGRESS"
  echo "------------"
  local found=0
  for d in "$RUNS_DIR"/*/; do
    [ -d "$d" ] || continue
    local base
    base="$(basename "$d")"
    [ "$base" = "completed" ] && continue
    [ "$base" = "abandoned" ] && continue

    local status
    status="$(grep '^status: ' "$d/state.md" 2>/dev/null | head -1 | sed 's/^status: //')"
    [ "$status" = "in-progress" ] || continue

    local step
    step="$(grep '^current_step: ' "$d/state.md" 2>/dev/null | head -1 | sed 's/^current_step: //')"
    echo "  $base  (step $step)"
    found=1
  done
  [ "$found" = 0 ] && echo "  (none)"

  echo ""
  echo "COMPLETED (last 5)"
  echo "-------------------"
  ls -t "$RUNS_DIR/completed" 2>/dev/null | head -5 | sed 's/^/  /'
  [ -z "$(ls "$RUNS_DIR/completed" 2>/dev/null)" ] && echo "  (none)"

  echo ""
  echo "ABANDONED (last 5)"
  echo "-------------------"
  ls -t "$RUNS_DIR/abandoned" 2>/dev/null | head -5 | sed 's/^/  /'
  [ -z "$(ls "$RUNS_DIR/abandoned" 2>/dev/null)" ] && echo "  (none)"
}

cmd_status() {
  local run_id="${1:-}"
  if [ -z "$run_id" ]; then
    echo "usage: workflow-state.sh status <run-id>" >&2
    return 1
  fi

  local run_dir=""
  for candidate in "$RUNS_DIR/$run_id" "$RUNS_DIR/completed/$run_id" "$RUNS_DIR/abandoned/$run_id"; do
    if [ -d "$candidate" ]; then
      run_dir="$candidate"
      break
    fi
  done

  if [ -z "$run_dir" ]; then
    echo "ERROR: run not found: $run_id" >&2
    return 2
  fi

  echo "=== $run_id ==="
  echo ""
  echo "--- state.md ---"
  cat "$run_dir/state.md"
  echo ""
  echo "--- last 5 events ---"
  tail -5 "$run_dir/events.jsonl" 2>/dev/null || echo "(no events)"
}

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------

cmd="${1:-}"
shift || true

case "$cmd" in
  start)          cmd_start "$@" ;;
  step-start)     cmd_step_start "$@" ;;
  step-complete)  cmd_step_complete "$@" ;;
  step-fail)      cmd_step_fail "$@" ;;
  finish)         cmd_finish "$@" ;;
  find-active)    cmd_find_active "$@" ;;
  list)           cmd_list "$@" ;;
  status)         cmd_status "$@" ;;
  *)
    echo "usage: workflow-state.sh <command> [args...]" >&2
    echo "commands: start | step-start | step-complete | step-fail | finish | find-active | list | status" >&2
    exit 1
    ;;
esac

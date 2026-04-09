#!/bin/bash
# session-start-workflow-detect.sh — Surface any in-progress workflow runs
# at session start so the user knows they can resume.
#
# Fails soft: never blocks session start.

set -uo pipefail

# Find the nearest vault directory walking up from cwd
detect_vault() {
  local dir="$(pwd)"
  while [ "$dir" != "/" ]; do
    if [ -d "$dir/vault/workflows/runs" ]; then
      echo "$dir/vault"
      return 0
    fi
    dir="$(dirname "$dir")"
  done
  return 1
}

VAULT_ROOT="$(detect_vault)" || exit 0
RUNS_DIR="$VAULT_ROOT/workflows/runs"

# Scan for in-progress runs (skip archive subdirs)
active_runs=()
for d in "$RUNS_DIR"/*/; do
  [ -d "$d" ] || continue
  base="$(basename "$d")"
  [ "$base" = "completed" ] && continue
  [ "$base" = "abandoned" ] && continue

  status="$(grep '^status: ' "$d/state.md" 2>/dev/null | head -1 | sed 's/^status: //')"
  [ "$status" = "in-progress" ] || continue

  active_runs+=("$base")
done

if [ ${#active_runs[@]} -eq 0 ]; then
  exit 0
fi

# Print a session-start notice to stderr (visible in the session header)
echo "" >&2
echo "[sentinel] You have ${#active_runs[@]} in-progress workflow run(s):" >&2
for run in "${active_runs[@]}"; do
  step="$(grep '^current_step: ' "$RUNS_DIR/$run/state.md" 2>/dev/null | head -1 | sed 's/^current_step: //')"
  workflow="$(grep '^workflow: ' "$RUNS_DIR/$run/state.md" 2>/dev/null | head -1 | sed 's/^workflow: //')"
  echo "  - $run  (workflow: $workflow, paused at step $step)" >&2
done
echo "" >&2
echo "[sentinel] Resume with:  /sentinel-workflow resume <run-id>" >&2
echo "[sentinel] See details with:  /sentinel-workflow status <run-id>" >&2
echo "" >&2

exit 0

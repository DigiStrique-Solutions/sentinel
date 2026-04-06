#!/bin/bash
# Ensure required system dependencies are installed.
# Runs as the first SessionStart hook — before any hook that needs jq.
# Uses a version-stamped marker so it only runs once per plugin version.

set -uo pipefail

VERSION=$(grep '"version"' "${CLAUDE_PLUGIN_ROOT}/package.json" 2>/dev/null | head -1 | tr -dc '0-9.')
MARKER_DIR="${CLAUDE_PLUGIN_DATA:-.}"
MARKER="${MARKER_DIR}/.deps-ok-${VERSION}"

# Skip if already verified for this version
if [ -f "$MARKER" ]; then
  exit 0
fi

MISSING=()

if ! command -v jq &>/dev/null; then
  MISSING+=("jq")
fi

if [ ${#MISSING[@]} -eq 0 ]; then
  mkdir -p "$MARKER_DIR"
  touch "$MARKER"
  exit 0
fi

echo "Sentinel: installing missing dependencies: ${MISSING[*]}..." >&2

if command -v brew &>/dev/null; then
  brew install "${MISSING[@]}" 2>&1 | tail -3 >&2
elif command -v apt-get &>/dev/null; then
  sudo apt-get install -y "${MISSING[@]}" 2>&1 | tail -3 >&2
elif command -v yum &>/dev/null; then
  sudo yum install -y "${MISSING[@]}" 2>&1 | tail -3 >&2
elif command -v apk &>/dev/null; then
  apk add "${MISSING[@]}" 2>&1 | tail -3 >&2
else
  echo "ERROR: Sentinel requires '${MISSING[*]}' but no supported package manager found (brew, apt, yum, apk)." >&2
  echo "Install manually: https://jqlang.github.io/jq/download/" >&2
  exit 1
fi

# Verify installation succeeded
for dep in "${MISSING[@]}"; do
  if ! command -v "$dep" &>/dev/null; then
    echo "ERROR: Failed to install '$dep'. Install manually: https://jqlang.github.io/jq/download/" >&2
    exit 1
  fi
done

echo "Sentinel: dependencies installed successfully." >&2
mkdir -p "$MARKER_DIR"
touch "$MARKER"
exit 0

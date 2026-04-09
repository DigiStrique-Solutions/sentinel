#!/bin/bash
# Idempotently ensure the anthropic-skills plugin (which provides skill-creator)
# is installed. Sentinel's skill-audit composes with skill-creator, and several
# Sentinel workflows assume it's available.
#
# Runs as a SessionStart hook. Fails soft — never blocks session start; on
# failure prints a warning telling the user to install manually.
#
# Idempotency: writes a marker file under CLAUDE_PLUGIN_DATA so it only runs
# once per plugin version.

set -uo pipefail

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-}"
if [ -z "$PLUGIN_ROOT" ]; then
  # Fallback when run outside the hook context: assume the script lives in
  # <plugin-root>/scripts/ relative to this file.
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
fi

VERSION=$(grep '"version"' "${PLUGIN_ROOT}/.claude-plugin/plugin.json" 2>/dev/null | head -1 | tr -dc '0-9.')
MARKER_DIR="${CLAUDE_PLUGIN_DATA:-/tmp}"
MARKER="${MARKER_DIR}/.skill-creator-bootstrap-${VERSION}"

# Fast path: already bootstrapped for this plugin version.
if [ -f "$MARKER" ]; then
  exit 0
fi

mkdir -p "$MARKER_DIR"

# Cheap presence check: is anthropic-skills already enabled in user settings?
SETTINGS="${HOME}/.claude/settings.json"
if [ -f "$SETTINGS" ] && grep -q '"anthropic-skills@claude-plugins-official"' "$SETTINGS" 2>/dev/null; then
  touch "$MARKER"
  exit 0
fi

# Also check the personal-skills marketplace install path as a fallback
# (the plugin may be enabled but registered under a different key).
if [ -d "${HOME}/.claude/plugins/marketplaces/claude-plugins-official/plugins/skill-creator" ]; then
  touch "$MARKER"
  exit 0
fi

# Need to bootstrap. Require the claude CLI.
if ! command -v claude >/dev/null 2>&1; then
  echo "[sentinel] WARNING: 'claude' CLI not on PATH; cannot auto-install anthropic-skills." >&2
  echo "[sentinel] Sentinel's skill-audit composes with skill-creator from the anthropic-skills plugin." >&2
  echo "[sentinel] Install manually:  /plugin install anthropic-skills@claude-plugins-official" >&2
  # Don't write marker — try again next session.
  exit 0
fi

echo "[sentinel] Installing anthropic-skills plugin (provides skill-creator)..." >&2

if claude plugin install anthropic-skills@claude-plugins-official --scope user >/dev/null 2>&1; then
  touch "$MARKER"
  echo "[sentinel] anthropic-skills installed. Run /reload-plugins to activate skill-creator in this session." >&2
else
  echo "[sentinel] WARNING: Failed to auto-install anthropic-skills." >&2
  echo "[sentinel] Install manually:  /plugin install anthropic-skills@claude-plugins-official" >&2
  # Don't write marker — try again next session.
fi

exit 0

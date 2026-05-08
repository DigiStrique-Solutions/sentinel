#!/bin/bash
# STOP HOOK (optional): Background knowledge extraction at session end.
#
# At session end, if the session was substantial (3+ files modified), spawn
# a background Python process that reads the transcript, calls the Anthropic
# API with a structured tool-use schema, and writes any extracted patterns,
# gotchas, investigations, or decisions to vault/<subdir>/.
#
# WHY THIS EXISTS AS A BACKGROUND PROCESS:
# Stop-hook stdout never reaches Claude on exit 0 (per the Claude Code hooks
# spec — see https://code.claude.com/docs/en/hooks "Exit code output"). The
# previous implementation cat-ed a "please extract patterns" prompt to stdout
# and was structurally inert. This wrapper backgrounds an extractor that does
# the work itself.
#
# REQUIREMENTS:
#   - .sentinel/config.json: hooks.background_extraction = true (opt-in)
#   - hooks.pattern_extraction = true (umbrella enable, set by presets)
#   - ANTHROPIC_API_KEY env var
#   - python3 on PATH
#
# Falls back to a no-op (clean exit 0) if any prerequisite is missing.

set -euo pipefail

INPUT=$(cat)
CWD=$(echo "$INPUT" | jq -r '.cwd // empty')
STOP_HOOK_ACTIVE=$(echo "$INPUT" | jq -r '.stop_hook_active // false')
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty')
TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.transcript_path // empty')

VAULT_DIR="${CWD}/vault"

# Don't run on re-entry
if [ "$STOP_HOOK_ACTIVE" = "true" ]; then
    exit 0
fi

# Graceful exit if vault doesn't exist
if [ ! -d "$VAULT_DIR" ]; then
    exit 0
fi

# Read config — both flags must be true to opt in
CONFIG_FILE="${CWD}/.sentinel/config.json"
PATTERN_EXTRACTION=false
BACKGROUND_EXTRACTION=false
if [ -f "$CONFIG_FILE" ]; then
    PATTERN_EXTRACTION=$(jq -r '.hooks.pattern_extraction // false' "$CONFIG_FILE" 2>/dev/null || echo "false")
    BACKGROUND_EXTRACTION=$(jq -r '.hooks.background_extraction // false' "$CONFIG_FILE" 2>/dev/null || echo "false")
fi
if [ "$PATTERN_EXTRACTION" != "true" ] || [ "$BACKGROUND_EXTRACTION" != "true" ]; then
    exit 0
fi

# Threshold: only run for sessions with 3+ modified files
SENTINEL_DIR="${CWD}/.sentinel"
if [ -n "$SESSION_ID" ]; then
    SHORT_ID="${SESSION_ID:0:12}"
    SENTINEL_DIR="${CWD}/.sentinel/sessions/${SHORT_ID}"
fi
MODIFIED_FILE="${SENTINEL_DIR}/modified-files.txt"

FILE_COUNT=0
if [ -f "$MODIFIED_FILE" ]; then
    FILE_COUNT=$(wc -l < "$MODIFIED_FILE" | tr -d ' ')
fi
if [ "$FILE_COUNT" -lt 3 ]; then
    exit 0
fi

# Hard requirements: API key + python3 + transcript file
if [ -z "${ANTHROPIC_API_KEY:-}" ]; then
    exit 0
fi
if ! command -v python3 >/dev/null 2>&1; then
    exit 0
fi
if [ -z "$TRANSCRIPT_PATH" ] || [ ! -f "$TRANSCRIPT_PATH" ]; then
    exit 0
fi

# Resolve plugin root and the extractor script
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"
EXTRACTOR="${PLUGIN_ROOT}/scripts/extract-knowledge.py"
if [ ! -f "$EXTRACTOR" ]; then
    exit 0
fi

# Prepare a log directory under .sentinel/ so users can audit what was spawned.
LOG_DIR="${CWD}/.sentinel"
mkdir -p "$LOG_DIR"
LOG_FILE="${LOG_DIR}/extraction.log"

# Spawn in background and detach so the Stop hook returns immediately.
# `nohup ... &` + `disown` ensures the process survives shell exit and does
# not block session end.
nohup python3 "$EXTRACTOR" \
    --transcript "$TRANSCRIPT_PATH" \
    --modified-files "$MODIFIED_FILE" \
    --vault "$VAULT_DIR" \
    >> "$LOG_FILE" 2>&1 &

disown 2>/dev/null || true

exit 0

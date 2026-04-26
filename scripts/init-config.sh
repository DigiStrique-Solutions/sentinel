#!/bin/bash
# init-config.sh — Single source of truth for creating/healing .sentinel/config.json
#
# Called by /sentinel-bootstrap (Step 8d) and /sentinel-doctor (Step 5b).
#
# Usage:
#   bash init-config.sh <project_dir> <preset_name> [mode]
#
# Args:
#   project_dir  — absolute path to the project root
#   preset_name  — minimal | standard | team
#   mode         — "init" (default, fail if exists) or "heal" (merge missing keys)
#
# Output: prints a JSON summary {created, healed, skipped, hooks_enabled} to stdout.

set -euo pipefail

PROJECT_DIR="${1:-}"
PRESET_NAME="${2:-standard}"
MODE="${3:-init}"

if [ -z "$PROJECT_DIR" ]; then
    echo "ERROR: project_dir required" >&2
    exit 2
fi

if [ ! -d "$PROJECT_DIR" ]; then
    echo "ERROR: $PROJECT_DIR does not exist" >&2
    exit 2
fi

# Resolve plugin root (where this script lives, two levels up from scripts/)
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
PRESET_DIR="${PLUGIN_ROOT}/templates/presets"
PRESET_FILE="${PRESET_DIR}/${PRESET_NAME}.json"

if [ ! -f "$PRESET_FILE" ]; then
    echo "ERROR: preset $PRESET_NAME not found at $PRESET_FILE" >&2
    exit 2
fi

# --- Resolve preset chain (handle "extends") ---
# Returns the merged hooks_config block as JSON.
resolve_hooks_config() {
    local preset="$1"
    local file="${PRESET_DIR}/${preset}.json"
    local extends
    extends=$(jq -r '.extends // empty' "$file")

    local base="{}"
    if [ -n "$extends" ]; then
        base=$(resolve_hooks_config "$extends")
    fi

    local own
    own=$(jq -c '.hooks_config // {}' "$file")

    # Merge: own keys override base keys
    jq -n --argjson b "$base" --argjson o "$own" '$b * $o'
}

HOOKS_CONFIG=$(resolve_hooks_config "$PRESET_NAME")

# Defaults block — these are the same across presets, only hooks differ.
DEFAULT_VAULT='{
  "repo_path": "vault",
  "global_enabled": true,
  "global_path": "~/.sentinel/vault"
}'

DEFAULT_THRESHOLDS='{
  "scope_warning_files": 3,
  "test_failure_warning": 2,
  "gotcha_staleness_days": 30,
  "investigation_warning_days": 7
}'

# Build the full default config from preset + defaults
build_defaults() {
    jq -n \
        --argjson vault "$DEFAULT_VAULT" \
        --argjson hooks "$HOOKS_CONFIG" \
        --argjson thresholds "$DEFAULT_THRESHOLDS" \
        --arg preset "$PRESET_NAME" \
        '{
            preset: $preset,
            vault: $vault,
            hooks: $hooks,
            thresholds: $thresholds
        }'
}

DEFAULTS=$(build_defaults)

# --- Write or heal config.json ---
SENTINEL_DIR="${PROJECT_DIR}/.sentinel"
CONFIG_FILE="${SENTINEL_DIR}/config.json"

mkdir -p "$SENTINEL_DIR"

CREATED=false
HEALED=false
SKIPPED=false
HEALED_KEYS=()

if [ ! -f "$CONFIG_FILE" ]; then
    # Fresh write
    echo "$DEFAULTS" | jq '.' > "$CONFIG_FILE"
    CREATED=true
else
    if [ "$MODE" = "init" ]; then
        # Init mode + file exists = skip (don't trample existing)
        SKIPPED=true
    else
        # Heal mode: deep-merge defaults into existing, but only add MISSING keys.
        # Existing user customizations are preserved.
        EXISTING=$(cat "$CONFIG_FILE")

        # The merge strategy: defaults * existing (existing wins on conflict).
        # But we want to TRACK which keys we added so we can report them.
        # Use jq to do the merge and diff.
        MERGED=$(jq -n --argjson d "$DEFAULTS" --argjson e "$EXISTING" '$d * $e')

        # Track which top-level keys + sub-keys were added.
        # Use has() rather than // because boolean false is a valid value.
        for section in vault hooks thresholds; do
            DEFAULT_KEYS=$(echo "$DEFAULTS" | jq -r --arg s "$section" '.[$s] // {} | keys[]')
            for key in $DEFAULT_KEYS; do
                PRESENT=$(echo "$EXISTING" | jq -r --arg s "$section" --arg k "$key" \
                    'if (.[$s] // {}) | has($k) then "yes" else "no" end')
                if [ "$PRESENT" = "no" ]; then
                    HEALED_KEYS+=("${section}.${key}")
                fi
            done
        done

        # Also heal preset key if missing
        PRESET_PRESENT=$(echo "$EXISTING" | jq -r 'if has("preset") then "yes" else "no" end')
        if [ "$PRESET_PRESENT" = "no" ]; then
            HEALED_KEYS+=("preset")
        fi

        if [ ${#HEALED_KEYS[@]} -gt 0 ]; then
            echo "$MERGED" | jq '.' > "$CONFIG_FILE"
            HEALED=true
        else
            SKIPPED=true
        fi
    fi
fi

# Count enabled hooks for summary
HOOKS_ENABLED=$(jq -r '.hooks | to_entries | map(select(.value == true)) | length' "$CONFIG_FILE")

# Build JSON summary
HEALED_KEYS_JSON=$(printf '%s\n' "${HEALED_KEYS[@]:-}" | jq -R . | jq -s 'map(select(. != ""))')

jq -n \
    --argjson created "$CREATED" \
    --argjson healed "$HEALED" \
    --argjson skipped "$SKIPPED" \
    --argjson hooks_enabled "$HOOKS_ENABLED" \
    --argjson healed_keys "$HEALED_KEYS_JSON" \
    --arg config_path "$CONFIG_FILE" \
    --arg preset "$PRESET_NAME" \
    '{
        config_path: $config_path,
        preset: $preset,
        created: $created,
        healed: $healed,
        skipped: $skipped,
        hooks_enabled: $hooks_enabled,
        healed_keys: $healed_keys
    }'

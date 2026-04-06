#!/bin/bash
# SESSION START HOOK: Sync shared Claude Code config from repo to ~/.claude/
# Runs BEFORE vault-loader. Skips if configVersion is already current.
#
# What it syncs:
#   - .claude/shared/agents/*.md  →  ~/.claude/agents/
#   - .claude/shared/rules/       →  ~/.claude/rules/
#   - Plugin enablement           →  ~/.claude/settings.json (merge, not overwrite)
#   - Missing plugins             →  claude plugin install (best-effort)

set -euo pipefail

INPUT=$(cat)
CWD=$(echo "$INPUT" | jq -r '.cwd // empty')

SHARED_DIR="${CWD}/.claude/shared"
MANIFEST="${SHARED_DIR}/manifest.json"
VERSION_FILE="${HOME}/.claude/.sentinel-sync-version"
GLOBAL_SETTINGS="${HOME}/.claude/settings.json"

# Guard: shared directory and manifest must exist
if [ ! -d "$SHARED_DIR" ] || [ ! -f "$MANIFEST" ]; then
    exit 0
fi

# Read configVersion from manifest
CONFIG_VERSION=$(jq -r '.configVersion // empty' "$MANIFEST" 2>/dev/null)
if [ -z "$CONFIG_VERSION" ]; then
    exit 0
fi

# Fast path: skip if already synced to this version
if [ -f "$VERSION_FILE" ]; then
    CURRENT_VERSION=$(cat "$VERSION_FILE" 2>/dev/null || echo "")
    if [ "$CURRENT_VERSION" = "$CONFIG_VERSION" ]; then
        exit 0
    fi
fi

SYNC_LOG=""

# --- 1. Sync agents (additive: overwrites shared agents, preserves personal ones) ---
if [ -d "${SHARED_DIR}/agents" ]; then
    mkdir -p "${HOME}/.claude/agents"
    AGENT_COUNT=0
    for f in "${SHARED_DIR}/agents/"*.md; do
        [ -f "$f" ] || continue
        cp "$f" "${HOME}/.claude/agents/"
        AGENT_COUNT=$((AGENT_COUNT + 1))
    done
    if [ "$AGENT_COUNT" -gt 0 ]; then
        SYNC_LOG="${SYNC_LOG}${AGENT_COUNT} agents. "
    fi
fi

# --- 2. Sync rules (only directories listed in manifest) ---
if [ -d "${SHARED_DIR}/rules" ]; then
    RULES_DIRS=$(jq -r '.rules.directories[]? // empty' "$MANIFEST" 2>/dev/null)
    if [ -n "$RULES_DIRS" ]; then
        mkdir -p "${HOME}/.claude/rules"
        # Copy README if present
        if [ -f "${SHARED_DIR}/rules/README.md" ]; then
            cp "${SHARED_DIR}/rules/README.md" "${HOME}/.claude/rules/README.md"
        fi
        RULE_COUNT=0
        for DIR in $RULES_DIRS; do
            if [ -d "${SHARED_DIR}/rules/${DIR}" ]; then
                mkdir -p "${HOME}/.claude/rules/${DIR}"
                cp -R "${SHARED_DIR}/rules/${DIR}/"* "${HOME}/.claude/rules/${DIR}/" 2>/dev/null || true
                RULE_COUNT=$((RULE_COUNT + 1))
            fi
        done
        if [ "$RULE_COUNT" -gt 0 ]; then
            SYNC_LOG="${SYNC_LOG}${RULE_COUNT} rule sets. "
        fi
    fi
fi

# --- 3. Merge global settings (enabledPlugins + extraKnownMarketplaces only) ---
TEMPLATE="${SHARED_DIR}/settings.global-template.json"
if [ -f "$TEMPLATE" ] && command -v jq &>/dev/null; then
    if [ ! -f "$GLOBAL_SETTINGS" ]; then
        # First time: copy template as base
        cp "$TEMPLATE" "$GLOBAL_SETTINGS"
        SYNC_LOG="${SYNC_LOG}Created global settings. "
    else
        # Merge: overlay plugin keys without touching other user keys
        MERGED=$(jq -s '
            .[0] as $existing |
            .[1] as $template |
            $existing
            | .enabledPlugins = (($existing.enabledPlugins // {}) * ($template.enabledPlugins // {}))
            | .extraKnownMarketplaces = (($existing.extraKnownMarketplaces // {}) * ($template.extraKnownMarketplaces // {}))
        ' "$GLOBAL_SETTINGS" "$TEMPLATE" 2>/dev/null)
        if [ -n "$MERGED" ]; then
            echo "$MERGED" > "${GLOBAL_SETTINGS}.tmp" && mv "${GLOBAL_SETTINGS}.tmp" "$GLOBAL_SETTINGS"
            SYNC_LOG="${SYNC_LOG}Settings merged. "
        fi
    fi
fi

# --- 4. Install missing plugins (best-effort, non-blocking) ---
if command -v claude &>/dev/null; then
    PLUGIN_COUNT=$(jq -r '.plugins.required | length' "$MANIFEST" 2>/dev/null || echo "0")
    INSTALLED_PLUGINS=""
    FAILED_PLUGINS=""

    # Collect missing plugins
    MISSING=()
    if [ "$PLUGIN_COUNT" -gt 0 ]; then
        for i in $(seq 0 $((PLUGIN_COUNT - 1))); do
            PLUGIN_NAME=$(jq -r ".plugins.required[$i].name" "$MANIFEST")
            PLUGIN_MKT=$(jq -r ".plugins.required[$i].marketplace" "$MANIFEST")
            PLUGIN_KEY="${PLUGIN_NAME}@${PLUGIN_MKT}"

            # Check if already installed by looking for the plugin directory
            if [ -d "${HOME}/.claude/plugins/cache/${PLUGIN_MKT}/${PLUGIN_NAME}" ]; then
                continue
            fi

            MISSING+=("$PLUGIN_KEY")
        done

        # Install missing plugins in parallel
        if [ ${#MISSING[@]} -gt 0 ]; then
            set +e
            PIDS=()
            for PLUGIN_KEY in "${MISSING[@]}"; do
                claude plugin install "$PLUGIN_KEY" &>/dev/null &
                PIDS+=($!)
            done
            # Wait for all installs with timeout awareness
            for PID in "${PIDS[@]}"; do
                wait "$PID" 2>/dev/null
                if [ $? -eq 0 ]; then
                    INSTALLED_PLUGINS="${INSTALLED_PLUGINS}installed "
                else
                    FAILED_PLUGINS="${FAILED_PLUGINS}failed "
                fi
            done
            set -e

            if [ -n "$INSTALLED_PLUGINS" ]; then
                SYNC_LOG="${SYNC_LOG}${#MISSING[@]} plugins installed. "
            fi
            if [ -n "$FAILED_PLUGINS" ]; then
                SYNC_LOG="${SYNC_LOG}WARN: Some plugins failed to install. "
            fi
        fi
    fi
fi

# --- 5. Write version stamp ---
mkdir -p "$(dirname "$VERSION_FILE")"
echo "$CONFIG_VERSION" > "$VERSION_FILE"

# --- Output summary ---
if [ -n "$SYNC_LOG" ]; then
    echo "CONFIG SYNC (v${CONFIG_VERSION}): Synced ${SYNC_LOG}"
fi

exit 0

#!/bin/bash
# Shared helper for resolving vault paths.
#
# Sentinel supports two vaults:
#   1. Repo vault (./vault/) — per-repo, committed with the code, default behavior
#   2. Global vault (~/.sentinel/vault/) — personal, cross-cutting, optionally its own git repo
#
# Read-path hooks load from BOTH. Write-path hooks only write to the repo vault.
# Users explicitly promote files from repo → global via /sentinel-promote.
#
# Usage from a hook script:
#   source "${CLAUDE_PLUGIN_ROOT}/scripts/resolve-vaults.sh"
#   REPO_VAULT=$(resolve_repo_vault "$CWD")
#   GLOBAL_VAULT=$(resolve_global_vault "$CWD")
#   VAULT_DIRS=$(resolve_all_vaults "$CWD")   # newline-separated list of existing vaults

# Resolve the repo vault path for a given working directory.
# Respects .sentinel/config.json `vault.repo_path` (relative or absolute).
# Default: "${cwd}/vault"
# Outputs the path whether or not it exists on disk.
resolve_repo_vault() {
    local cwd="$1"
    local config="${cwd}/.sentinel/config.json"
    local vault_path="vault"

    if [ -f "$config" ] && command -v jq &>/dev/null; then
        local configured
        configured=$(jq -r '.vault.repo_path // "vault"' "$config" 2>/dev/null || echo "vault")
        if [ -n "$configured" ] && [ "$configured" != "null" ]; then
            vault_path="$configured"
        fi
    fi

    if [[ "$vault_path" = /* ]]; then
        echo "$vault_path"
    else
        echo "${cwd}/${vault_path}"
    fi
}

# Resolve the global vault path for a given working directory.
# Respects .sentinel/config.json `vault.global_enabled` and `vault.global_path`.
# Default: enabled=true, path="~/.sentinel/vault"
# Outputs empty string when globally disabled.
resolve_global_vault() {
    local cwd="$1"
    local config="${cwd}/.sentinel/config.json"
    local enabled="true"
    local global_path="${HOME}/.sentinel/vault"

    if [ -f "$config" ] && command -v jq &>/dev/null; then
        local configured_enabled configured_path
        # NOTE: jq's `//` operator treats `false` as null, so `.x // true`
        # returns `true` even when `.x` is literally `false`. Check the raw
        # value instead.
        configured_enabled=$(jq -r '.vault.global_enabled' "$config" 2>/dev/null || echo "null")
        configured_path=$(jq -r '.vault.global_path // empty' "$config" 2>/dev/null || echo "")

        if [ "$configured_enabled" = "false" ]; then
            enabled="false"
        fi

        if [ -n "$configured_path" ] && [ "$configured_path" != "null" ]; then
            # Expand ~ manually — jq doesn't do shell expansion
            global_path="${configured_path/#\~/$HOME}"
        fi
    fi

    if [ "$enabled" = "false" ]; then
        echo ""
        return 0
    fi

    echo "$global_path"
}

# Resolve both vaults and output existing ones as a newline-separated list.
# Order: repo vault first, then global vault.
# Use in hooks that read from both layers.
resolve_all_vaults() {
    local cwd="$1"
    local repo global

    repo=$(resolve_repo_vault "$cwd")
    global=$(resolve_global_vault "$cwd")

    if [ -n "$repo" ] && [ -d "$repo" ]; then
        echo "$repo"
    fi
    if [ -n "$global" ] && [ -d "$global" ] && [ "$global" != "$repo" ]; then
        echo "$global"
    fi
}

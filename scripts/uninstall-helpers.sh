#!/usr/bin/env bash
# uninstall-helpers.sh — discovery and revert functions for /sentinel-uninstall.
#
# Dispatchable library: either source it to use the functions directly, or
# invoke it with a function name as the first argument:
#
#   ./uninstall-helpers.sh discover-project /path/to/repo
#   ./uninstall-helpers.sh revert-settings-json /path/to/repo
#
# All functions respect DRY_RUN=1 — if set, no destructive action is taken,
# and every mutating function prints what it WOULD do instead of doing it.
#
# All functions are idempotent: safe to re-run after a partial failure.

set -uo pipefail

# --- Utilities -------------------------------------------------------------

_un_log() {
    echo "[uninstall] $*" >&2
}

_un_dry() {
    if [ "${DRY_RUN:-0}" = "1" ]; then
        echo "[DRY RUN] $*" >&2
        return 0
    fi
    return 1
}

_un_require_jq() {
    if ! command -v jq &>/dev/null; then
        echo "ERROR: jq is required for uninstall. Run 'brew install jq' (macOS) or 'sudo apt install jq' (Linux)." >&2
        return 1
    fi
}

_un_plugin_root() {
    # Resolve the plugin root (directory containing this script's parent).
    if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -d "$CLAUDE_PLUGIN_ROOT" ]; then
        echo "$CLAUDE_PLUGIN_ROOT"
    else
        # When sourced, BASH_SOURCE[0] is the path to this file.
        local self="${BASH_SOURCE[0]:-$0}"
        local script_dir
        script_dir=$(cd "$(dirname "$self")" && pwd)
        cd "$script_dir/.." && pwd
    fi
}

_un_repo_name() {
    local cwd="$1"
    basename "$cwd"
}

# --- Preflight -------------------------------------------------------------

# un_preflight_check <cwd>
# Returns 0 if the cwd is safe to uninstall from, non-zero otherwise.
# Checks:
#   1. jq is available
#   2. If inside a git repo, the tree has no uncommitted changes
un_preflight_check() {
    local cwd="${1:-$PWD}"

    _un_require_jq || return 10

    if git -C "$cwd" rev-parse --is-inside-work-tree &>/dev/null; then
        local status
        status=$(git -C "$cwd" status --porcelain 2>/dev/null || echo "")
        if [ -n "$status" ]; then
            echo "ERROR: Uncommitted changes detected in $cwd." >&2
            echo "Commit or stash them first — uninstall touches git state and should not run against a dirty tree." >&2
            return 11
        fi
    fi

    return 0
}

# --- Discovery -------------------------------------------------------------

# un_discover_project <cwd>
# Emits a JSON report of every Sentinel artifact in the project.
un_discover_project() {
    local cwd="${1:-$PWD}"

    _un_require_jq || return 1

    local repo_name
    repo_name=$(_un_repo_name "$cwd")

    # Vault
    local vault_path="${cwd}/vault"
    local vault_exists=false vault_files=0 vault_size=0
    if [ -d "$vault_path" ]; then
        vault_exists=true
        vault_files=$(find "$vault_path" -type f 2>/dev/null | wc -l | tr -d ' ')
        if [[ "$OSTYPE" == "darwin"* ]]; then
            vault_size=$(find "$vault_path" -type f -exec stat -f%z {} + 2>/dev/null | awk '{s+=$1} END {print s+0}')
        else
            vault_size=$(find "$vault_path" -type f -printf '%s\n' 2>/dev/null | awk '{s+=$1} END {print s+0}')
        fi
    fi

    # .sentinel state
    local sentinel_path="${cwd}/.sentinel"
    local sentinel_exists=false sentinel_sessions=0
    if [ -d "$sentinel_path" ]; then
        sentinel_exists=true
        if [ -d "${sentinel_path}/sessions" ]; then
            sentinel_sessions=$(find "${sentinel_path}/sessions" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')
        fi
    fi

    # CLAUDE.md — heuristic section detection
    local claude_md_path="${cwd}/CLAUDE.md"
    local claude_md_exists=false
    local claude_md_sections_json="[]"
    if [ -f "$claude_md_path" ]; then
        claude_md_exists=true
        claude_md_sections_json=$(_un_find_claude_md_sections "$claude_md_path")
    fi

    # .claude/settings.json — count sentinel-added permission patterns
    local settings_json_path="${cwd}/.claude/settings.json"
    local settings_exists=false sentinel_perm_count=0
    if [ -f "$settings_json_path" ]; then
        settings_exists=true
        sentinel_perm_count=$(_un_count_sentinel_permissions "$settings_json_path")
    fi

    # .gitattributes
    local gitattributes_path="${cwd}/.gitattributes"
    local gitattributes_exists=false has_sentinel_line=false
    if [ -f "$gitattributes_path" ]; then
        gitattributes_exists=true
        if grep -qE '^vault/\*\*/\*\.md\s+merge=sentinel-vault' "$gitattributes_path" 2>/dev/null; then
            has_sentinel_line=true
        fi
    fi

    # .git/config — sentinel merge driver
    local has_git_merge_driver=false
    if [ -d "${cwd}/.git" ] && git -C "$cwd" config --get merge.sentinel-vault.driver &>/dev/null; then
        has_git_merge_driver=true
    fi

    # scripts/vault-merge-driver.sh
    local merge_driver_script="${cwd}/scripts/vault-merge-driver.sh"
    local merge_driver_script_exists=false
    [ -f "$merge_driver_script" ] && merge_driver_script_exists=true

    # .claude/shared/
    local shared_dir="${cwd}/.claude/shared"
    local shared_dir_exists=false
    [ -d "$shared_dir" ] && shared_dir_exists=true

    # Git branches — sentinel/* and autoresearch/*
    local sentinel_branches_json="[]"
    local autoresearch_branches_json="[]"
    if git -C "$cwd" rev-parse --is-inside-work-tree &>/dev/null; then
        local sentinel_branches
        sentinel_branches=$(git -C "$cwd" branch --list 'sentinel/*' --format='%(refname:short)' 2>/dev/null || echo "")
        if [ -n "$sentinel_branches" ]; then
            sentinel_branches_json=$(echo "$sentinel_branches" | jq -R . | jq -sc .)
        fi
        local autoresearch_branches
        autoresearch_branches=$(git -C "$cwd" branch --list 'autoresearch/*' --format='%(refname:short)' 2>/dev/null || echo "")
        if [ -n "$autoresearch_branches" ]; then
            autoresearch_branches_json=$(echo "$autoresearch_branches" | jq -R . | jq -sc .)
        fi
    fi

    # Ejected plugin files
    local ejected_hooks_count=0 ejected_agents_count=0 ejected_skills_count=0 ejected_rules_count=0
    [ -d "${cwd}/.claude/hooks" ] && ejected_hooks_count=$(find "${cwd}/.claude/hooks" -name "*.sh" -type f 2>/dev/null | wc -l | tr -d ' ')
    [ -d "${cwd}/.claude/agents" ] && ejected_agents_count=$(find "${cwd}/.claude/agents" -name "*.md" -type f 2>/dev/null | wc -l | tr -d ' ')
    [ -d "${cwd}/.claude/skills" ] && ejected_skills_count=$(find "${cwd}/.claude/skills" -name "*.md" -type f 2>/dev/null | wc -l | tr -d ' ')
    [ -d "${cwd}/.claude/rules" ] && ejected_rules_count=$(find "${cwd}/.claude/rules" -name "*.md" -type f 2>/dev/null | wc -l | tr -d ' ')

    jq -n \
        --arg cwd "$cwd" \
        --arg repo_name "$repo_name" \
        --arg vault_path "$vault_path" \
        --argjson vault_exists "$vault_exists" \
        --argjson vault_files "$vault_files" \
        --argjson vault_size "$vault_size" \
        --arg sentinel_path "$sentinel_path" \
        --argjson sentinel_exists "$sentinel_exists" \
        --argjson sentinel_sessions "$sentinel_sessions" \
        --arg claude_md_path "$claude_md_path" \
        --argjson claude_md_exists "$claude_md_exists" \
        --argjson claude_md_sections "$claude_md_sections_json" \
        --arg settings_path "$settings_json_path" \
        --argjson settings_exists "$settings_exists" \
        --argjson sentinel_perm_count "$sentinel_perm_count" \
        --argjson gitattributes_exists "$gitattributes_exists" \
        --argjson has_sentinel_line "$has_sentinel_line" \
        --argjson has_git_merge_driver "$has_git_merge_driver" \
        --argjson merge_driver_script_exists "$merge_driver_script_exists" \
        --argjson shared_dir_exists "$shared_dir_exists" \
        --argjson sentinel_branches "$sentinel_branches_json" \
        --argjson autoresearch_branches "$autoresearch_branches_json" \
        --argjson ejected_hooks "$ejected_hooks_count" \
        --argjson ejected_agents "$ejected_agents_count" \
        --argjson ejected_skills "$ejected_skills_count" \
        --argjson ejected_rules "$ejected_rules_count" \
        '{
            cwd: $cwd,
            repo_name: $repo_name,
            vault: {
                exists: $vault_exists,
                path: $vault_path,
                files: $vault_files,
                size_bytes: $vault_size
            },
            sentinel_state: {
                exists: $sentinel_exists,
                path: $sentinel_path,
                sessions: $sentinel_sessions
            },
            claude_md: {
                exists: $claude_md_exists,
                path: $claude_md_path,
                sentinel_sections: $claude_md_sections
            },
            settings_json: {
                exists: $settings_exists,
                path: $settings_path,
                sentinel_permissions: $sentinel_perm_count
            },
            gitattributes: {
                exists: $gitattributes_exists,
                has_sentinel_line: $has_sentinel_line
            },
            git_config: {
                has_sentinel_merge_driver: $has_git_merge_driver
            },
            merge_driver_script: {
                exists: $merge_driver_script_exists
            },
            shared_dir: {
                exists: $shared_dir_exists
            },
            git_branches: {
                sentinel: $sentinel_branches,
                autoresearch: $autoresearch_branches
            },
            ejected: {
                hooks: $ejected_hooks,
                agents: $ejected_agents,
                skills: $ejected_skills,
                rules: $ejected_rules
            }
        }'
}

# un_discover_global
# Emits JSON describing global (~/ and ~/.sentinel/) Sentinel state.
un_discover_global() {
    _un_require_jq || return 1

    local global_vault="${HOME}/.sentinel/vault"
    local gv_exists=false gv_files=0 gv_is_git=false gv_has_remote=false
    if [ -d "$global_vault" ]; then
        gv_exists=true
        gv_files=$(find "$global_vault" -type f -name "*.md" 2>/dev/null | wc -l | tr -d ' ')
        if [ -d "${global_vault}/.git" ]; then
            gv_is_git=true
            if git -C "$global_vault" remote -v 2>/dev/null | grep -q .; then
                gv_has_remote=true
            fi
        fi
    fi

    local plugin_data="${HOME}/.sentinel"
    local pd_exists=false pd_has_other_files=false
    if [ -d "$plugin_data" ]; then
        pd_exists=true
        # Does it contain anything besides vault/ and backups/?
        local other_items
        other_items=$(find "$plugin_data" -mindepth 1 -maxdepth 1 ! -name vault ! -name backups 2>/dev/null | head -1)
        [ -n "$other_items" ] && pd_has_other_files=true
    fi

    local global_settings="${HOME}/.claude/settings.json"
    local gs_exists=false
    [ -f "$global_settings" ] && gs_exists=true

    local sync_version="${HOME}/.claude/.sentinel-sync-version"
    local sv_exists=false
    [ -f "$sync_version" ] && sv_exists=true

    jq -n \
        --arg gv_path "$global_vault" \
        --argjson gv_exists "$gv_exists" \
        --argjson gv_files "$gv_files" \
        --argjson gv_is_git "$gv_is_git" \
        --argjson gv_has_remote "$gv_has_remote" \
        --arg pd_path "$plugin_data" \
        --argjson pd_exists "$pd_exists" \
        --argjson pd_has_other_files "$pd_has_other_files" \
        --argjson gs_exists "$gs_exists" \
        --argjson sv_exists "$sv_exists" \
        '{
            global_vault: {
                exists: $gv_exists,
                path: $gv_path,
                files: $gv_files,
                is_git_repo: $gv_is_git,
                has_remote: $gv_has_remote
            },
            plugin_data: {
                exists: $pd_exists,
                path: $pd_path,
                has_non_vault_files: $pd_has_other_files
            },
            global_claude_settings: {
                exists: $gs_exists
            },
            sync_version_marker: {
                exists: $sv_exists
            }
        }'
}

# Internal: find Sentinel-added sections in CLAUDE.md by heading fingerprint.
# Outputs JSON array of {heading, line_start, line_end, confidence}.
_un_find_claude_md_sections() {
    local file="$1"
    if [ ! -f "$file" ]; then
        echo "[]"
        return 0
    fi

    # Known Sentinel section headings from templates/claude-md/{minimal,standard,team}.md
    # Confidence: "high" = unmistakable (only Sentinel would write this)
    #             "medium" = common heading, requires content inspection
    local -a high_confidence=(
        "## Quality Standards (auto-loaded)"
        "## Workflows — Read Before Starting Work"
        "## Mandatory Behaviors"
        "## Critical Rules"
        "## Essential Patterns"
        "## Compact Instructions"
        "## Autonomy"
    )

    local result="[]"
    for heading in "${high_confidence[@]}"; do
        local line_start
        line_start=$(grep -nF "$heading" "$file" 2>/dev/null | head -1 | cut -d: -f1)
        if [ -n "$line_start" ]; then
            # Find next top-level heading (## ) after this one, or EOF.
            # Note: awk's exit still runs END blocks, so we use a found flag.
            local line_end
            line_end=$(awk -v start="$line_start" '
                NR > start && /^## / { print NR - 1; found=1; exit }
                END { if (!found) print NR }
            ' "$file")
            # Escape heading for JSON
            result=$(echo "$result" | jq \
                --arg h "$heading" \
                --argjson ls "$line_start" \
                --argjson le "$line_end" \
                --arg conf "high" \
                '. + [{heading: $h, line_start: $ls, line_end: $le, confidence: $conf}]')
        fi
    done

    echo "$result"
}

# Internal: count how many entries in permissions.allow match Sentinel's
# known permission patterns (from configure-permissions.sh).
_un_count_sentinel_permissions() {
    local settings_file="$1"
    if [ ! -f "$settings_file" ]; then
        echo "0"
        return 0
    fi

    local patterns_json
    patterns_json=$(_un_load_sentinel_permissions)
    [ -z "$patterns_json" ] && { echo "0"; return 0; }

    jq --argjson patterns "$patterns_json" '
        (.permissions.allow // []) as $allow |
        [$allow[] | select(. as $p | $patterns | index($p))] | length
    ' "$settings_file" 2>/dev/null || echo "0"
}

# Internal: extract a single bash array literal from a script by parsing
# its text. Looks for `NAME=(` on a line, then captures every "..." entry
# until the closing `)`. This is safer than sourcing the script, which has
# side effects (mkdir, file writes) and set -e propagation.
_un_extract_permission_array() {
    local array_name="$1"
    local script_file="$2"
    awk -v name="$array_name" '
        $0 ~ "^" name "=\\(" { capture = 1; next }
        capture && /^\)/ { capture = 0; exit }
        capture {
            # strip leading whitespace
            sub(/^[[:space:]]+/, "")
            # skip comments and blank lines
            if (/^#/ || /^$/) next
            # strip surrounding double quotes
            if (match($0, /^"[^"]*"/)) {
                val = substr($0, RSTART + 1, RLENGTH - 2)
                print val
            }
        }
    ' "$script_file"
}

# Internal: load the full set of Sentinel-added permission patterns.
# Parses configure-permissions.sh directly to avoid the side effects of
# sourcing it (mkdir, settings.json write, set -e propagation).
# Returns a JSON array of strings.
_un_load_sentinel_permissions() {
    local plugin_root
    plugin_root=$(_un_plugin_root)
    local cp_script="${plugin_root}/scripts/configure-permissions.sh"

    if [ ! -f "$cp_script" ]; then
        echo "[]"
        return 0
    fi

    {
        _un_extract_permission_array COMMON_PERMISSIONS "$cp_script"
        _un_extract_permission_array PYTHON_PERMISSIONS "$cp_script"
        _un_extract_permission_array TYPESCRIPT_PERMISSIONS "$cp_script"
    } | jq -R . | jq -sc 'unique'
}

# --- Backup ----------------------------------------------------------------

# un_create_backup <cwd> [backup_name]
# Creates a tarball of everything Sentinel has touched in <cwd>.
# Returns the backup path on success, non-zero on failure.
un_create_backup() {
    local cwd="${1:-$PWD}"
    local name="${2:-$(_un_repo_name "$cwd")}"
    local ts
    ts=$(date +%Y-%m-%d-%H%M%S)
    local backup_dir="${HOME}/.sentinel/backups"
    local backup_file="${backup_dir}/sentinel-backup-${name}-${ts}.tar.gz"

    if _un_dry "create backup at $backup_file"; then
        echo "$backup_file"
        return 0
    fi

    mkdir -p "$backup_dir" || {
        echo "ERROR: Cannot create backup directory $backup_dir" >&2
        return 1
    }

    # Build list of paths that exist (tar fails hard on missing args).
    local -a paths=()
    [ -d "${cwd}/vault" ] && paths+=("vault")
    [ -d "${cwd}/.sentinel" ] && paths+=(".sentinel")
    [ -f "${cwd}/CLAUDE.md" ] && paths+=("CLAUDE.md")
    [ -d "${cwd}/.claude" ] && paths+=(".claude")
    [ -f "${cwd}/.gitattributes" ] && paths+=(".gitattributes")
    [ -f "${cwd}/scripts/vault-merge-driver.sh" ] && paths+=("scripts/vault-merge-driver.sh")

    if [ ${#paths[@]} -eq 0 ]; then
        _un_log "nothing to back up in $cwd"
        return 0
    fi

    if ! tar -czf "$backup_file" -C "$cwd" "${paths[@]}" 2>/dev/null; then
        echo "ERROR: Backup creation failed. Aborting uninstall." >&2
        rm -f "$backup_file" 2>/dev/null
        return 1
    fi

    _un_log "backup created: $backup_file"
    echo "$backup_file"
}

# --- Revert functions ------------------------------------------------------

# un_delete_vault <cwd>
un_delete_vault() {
    local cwd="${1:-$PWD}"
    local vault="${cwd}/vault"
    if [ ! -d "$vault" ]; then
        _un_log "no vault to delete"
        return 0
    fi
    if _un_dry "rm -rf $vault"; then return 0; fi
    rm -rf "$vault"
    _un_log "deleted $vault"
}

# un_delete_sentinel_state <cwd>
un_delete_sentinel_state() {
    local cwd="${1:-$PWD}"
    local sd="${cwd}/.sentinel"
    if [ ! -d "$sd" ]; then
        _un_log "no .sentinel/ to delete"
        return 0
    fi
    if _un_dry "rm -rf $sd"; then return 0; fi
    rm -rf "$sd"
    _un_log "deleted $sd"
}

# un_revert_claude_md <cwd>
# Removes Sentinel-added sections by heading fingerprint.
# Writes to a temp file and atomically renames on success.
un_revert_claude_md() {
    local cwd="${1:-$PWD}"
    local file="${cwd}/CLAUDE.md"
    if [ ! -f "$file" ]; then
        _un_log "no CLAUDE.md to revert"
        return 0
    fi

    local sections
    sections=$(_un_find_claude_md_sections "$file")
    local count
    count=$(echo "$sections" | jq 'length')
    if [ "$count" = "0" ]; then
        _un_log "no Sentinel sections found in CLAUDE.md"
        return 0
    fi

    if _un_dry "remove $count Sentinel section(s) from $file"; then
        echo "$sections" | jq -r '.[] | "  - \(.heading) (lines \(.line_start)-\(.line_end))"' >&2
        return 0
    fi

    # Build a sed script that deletes each section's line range.
    # Process sections in reverse line order so earlier line numbers
    # remain valid as we delete later ones.
    local tmp
    tmp=$(mktemp) || return 1
    cp "$file" "$tmp" || { rm -f "$tmp"; return 1; }

    local ranges
    ranges=$(echo "$sections" | jq -r 'sort_by(-.line_start) | .[] | "\(.line_start),\(.line_end)d"')
    while IFS= read -r range; do
        [ -z "$range" ] && continue
        if [[ "$OSTYPE" == "darwin"* ]]; then
            sed -i '' -e "$range" "$tmp"
        else
            sed -i -e "$range" "$tmp"
        fi
    done <<< "$ranges"

    # Collapse any 3+ consecutive blank lines to 2 (tidy up after removals).
    awk 'BEGIN{blank=0} /^$/{blank++; if(blank<=2)print; next} {blank=0; print}' "$tmp" > "${tmp}.2"
    mv "${tmp}.2" "$tmp"

    mv "$tmp" "$file"
    _un_log "removed $count Sentinel section(s) from CLAUDE.md"
}

# un_revert_settings_json <cwd>
# Removes Sentinel-added permission patterns from .claude/settings.json.
un_revert_settings_json() {
    local cwd="${1:-$PWD}"
    local file="${cwd}/.claude/settings.json"
    if [ ! -f "$file" ]; then
        _un_log "no .claude/settings.json to revert"
        return 0
    fi

    local patterns_json
    patterns_json=$(_un_load_sentinel_permissions)
    if [ -z "$patterns_json" ] || [ "$patterns_json" = "[]" ]; then
        _un_log "could not load Sentinel permission patterns — skipping settings.json"
        return 0
    fi

    local removed_count
    removed_count=$(jq --argjson patterns "$patterns_json" '
        (.permissions.allow // []) as $allow |
        [$allow[] | select(. as $p | $patterns | index($p))] | length
    ' "$file" 2>/dev/null || echo "0")

    if [ "$removed_count" = "0" ]; then
        _un_log "no Sentinel permissions found in settings.json"
        return 0
    fi

    if _un_dry "remove $removed_count Sentinel permission(s) from $file"; then
        return 0
    fi

    local tmp
    tmp=$(mktemp) || return 1
    jq --argjson patterns "$patterns_json" '
        if .permissions.allow then
            .permissions.allow = [.permissions.allow[] | select(. as $p | $patterns | index($p) | not)]
        else . end
        |
        # If permissions.allow is now empty, remove it; if permissions is now empty, remove that too.
        if (.permissions.allow // []) == [] then del(.permissions.allow) else . end
        |
        if (.permissions // {}) == {} then del(.permissions) else . end
    ' "$file" > "$tmp" 2>/dev/null || { rm -f "$tmp"; _un_log "jq failed on settings.json"; return 1; }

    # If the resulting file is just "{}", delete it entirely.
    local remaining
    remaining=$(jq -c . "$tmp" 2>/dev/null || echo "null")
    if [ "$remaining" = "{}" ]; then
        rm -f "$tmp" "$file"
        # Remove .claude dir if now empty
        rmdir "${cwd}/.claude" 2>/dev/null || true
        _un_log "removed $removed_count Sentinel permissions and deleted now-empty settings.json"
    else
        mv "$tmp" "$file"
        _un_log "removed $removed_count Sentinel permissions from settings.json"
    fi
}

# un_revert_gitattributes <cwd>
un_revert_gitattributes() {
    local cwd="${1:-$PWD}"
    local file="${cwd}/.gitattributes"
    if [ ! -f "$file" ]; then
        _un_log "no .gitattributes to revert"
        return 0
    fi
    if ! grep -qE '^vault/\*\*/\*\.md\s+merge=sentinel-vault' "$file" 2>/dev/null; then
        _un_log "no Sentinel line in .gitattributes"
        return 0
    fi
    if _un_dry "remove sentinel-vault line from $file"; then return 0; fi

    local tmp
    tmp=$(mktemp) || return 1
    grep -vE '^vault/\*\*/\*\.md\s+merge=sentinel-vault' "$file" > "$tmp" || true

    if [ ! -s "$tmp" ]; then
        rm -f "$tmp" "$file"
        _un_log "removed sentinel-vault line; .gitattributes was empty and is now deleted"
    else
        mv "$tmp" "$file"
        _un_log "removed sentinel-vault line from .gitattributes"
    fi
}

# un_revert_git_config <cwd>
un_revert_git_config() {
    local cwd="${1:-$PWD}"
    if ! git -C "$cwd" rev-parse --is-inside-work-tree &>/dev/null; then
        _un_log "not a git repo — skipping git config revert"
        return 0
    fi
    if ! git -C "$cwd" config --get merge.sentinel-vault.driver &>/dev/null; then
        _un_log "no merge.sentinel-vault.driver in git config"
        return 0
    fi
    if _un_dry "git config --unset-all merge.sentinel-vault.driver"; then return 0; fi
    git -C "$cwd" config --unset-all merge.sentinel-vault.driver 2>/dev/null || true
    # Also remove the section if empty
    git -C "$cwd" config --remove-section merge.sentinel-vault 2>/dev/null || true
    _un_log "removed merge.sentinel-vault.driver from git config"
}

# un_delete_merge_driver_script <cwd>
un_delete_merge_driver_script() {
    local cwd="${1:-$PWD}"
    local file="${cwd}/scripts/vault-merge-driver.sh"
    if [ ! -f "$file" ]; then
        _un_log "no vault-merge-driver.sh to delete"
        return 0
    fi
    if _un_dry "rm $file"; then return 0; fi
    rm -f "$file"
    # Remove scripts/ dir if now empty
    rmdir "${cwd}/scripts" 2>/dev/null || true
    _un_log "deleted $file"
}

# un_delete_shared_dir <cwd>
un_delete_shared_dir() {
    local cwd="${1:-$PWD}"
    local d="${cwd}/.claude/shared"
    if [ ! -d "$d" ]; then
        _un_log "no .claude/shared/ to delete"
        return 0
    fi
    if _un_dry "rm -rf $d"; then return 0; fi
    rm -rf "$d"
    rmdir "${cwd}/.claude" 2>/dev/null || true
    _un_log "deleted $d"
}

# un_delete_git_branches <cwd> <mode>
# mode: merged-only (default) | all
un_delete_git_branches() {
    local cwd="${1:-$PWD}"
    local mode="${2:-merged-only}"

    if ! git -C "$cwd" rev-parse --is-inside-work-tree &>/dev/null; then
        _un_log "not a git repo — skipping branch deletion"
        return 0
    fi

    local current
    current=$(git -C "$cwd" branch --show-current 2>/dev/null || echo "")

    local -a candidates=()
    while IFS= read -r b; do
        [ -z "$b" ] && continue
        [ "$b" = "$current" ] && continue
        candidates+=("$b")
    done < <(git -C "$cwd" branch --list 'sentinel/*' 'autoresearch/*' --format='%(refname:short)' 2>/dev/null)

    if [ ${#candidates[@]} -eq 0 ]; then
        _un_log "no sentinel/* or autoresearch/* branches to delete"
        return 0
    fi

    local -a to_delete=()
    if [ "$mode" = "all" ]; then
        to_delete=("${candidates[@]}")
    else
        # Only delete branches that are merged into HEAD.
        # Note: git branch --merged takes an OPTIONAL commit-ish arg, so
        # --format must come BEFORE --merged or git parses --format as the
        # commit and bombs out with "malformed object name".
        local merged
        merged=$(git -C "$cwd" branch --format='%(refname:short)' --merged HEAD 2>/dev/null || echo "")
        for b in "${candidates[@]}"; do
            if echo "$merged" | grep -qx "$b"; then
                to_delete+=("$b")
            fi
        done
    fi

    if [ ${#to_delete[@]} -eq 0 ]; then
        _un_log "no merged sentinel/autoresearch branches to delete (use mode=all to force)"
        return 0
    fi

    if _un_dry "delete ${#to_delete[@]} branch(es): ${to_delete[*]}"; then return 0; fi

    local flag="-d"
    [ "$mode" = "all" ] && flag="-D"

    local deleted=0
    for b in "${to_delete[@]}"; do
        if git -C "$cwd" branch "$flag" "$b" &>/dev/null; then
            deleted=$((deleted + 1))
        fi
    done
    _un_log "deleted $deleted branch(es)"
}

# un_delete_global_vault
# Deletes ~/.sentinel/vault/. Caller must have already confirmed.
un_delete_global_vault() {
    local gv="${HOME}/.sentinel/vault"
    if [ ! -d "$gv" ]; then
        _un_log "no global vault to delete"
        return 0
    fi
    if _un_dry "rm -rf $gv"; then return 0; fi
    rm -rf "$gv"
    _un_log "deleted global vault at $gv"
}

# un_revert_global_claude_settings
# Removes the sync-version marker. Does NOT touch ~/.claude/settings.json
# content itself — we don't have enough fidelity to know what was added.
un_revert_global_claude_settings() {
    local marker="${HOME}/.claude/.sentinel-sync-version"
    if [ -f "$marker" ]; then
        if _un_dry "rm $marker"; then return 0; fi
        rm -f "$marker"
        _un_log "removed $marker"
    fi
}

# un_delete_plugin_data
# Removes ~/.sentinel/ but preserves backups/ subdirectory.
un_delete_plugin_data() {
    local pd="${HOME}/.sentinel"
    if [ ! -d "$pd" ]; then
        _un_log "no plugin data to delete"
        return 0
    fi
    if _un_dry "remove $pd (preserving backups/ and vault/)"; then return 0; fi

    # Remove everything except backups/ and vault/
    find "$pd" -mindepth 1 -maxdepth 1 ! -name backups ! -name vault -exec rm -rf {} + 2>/dev/null || true
    _un_log "cleaned $pd (preserved backups/ and vault/)"
}

# --- Dispatcher ------------------------------------------------------------

# When called as a script (not sourced), dispatch to a function by name.
if [ "${BASH_SOURCE[0]:-$0}" = "$0" ]; then
    cmd="${1:-}"
    if [ -z "$cmd" ]; then
        cat <<'USAGE' >&2
Usage: uninstall-helpers.sh <command> [args...]

Discovery:
  discover-project <cwd>      Emit JSON report of project-level Sentinel artifacts
  discover-global             Emit JSON report of global Sentinel artifacts
  preflight-check <cwd>       Verify cwd is safe to uninstall (exits 0 OK, non-zero FAIL)

Backup:
  create-backup <cwd> [name]  Create backup tarball; prints path on success

Project reverts:
  delete-vault <cwd>
  delete-sentinel-state <cwd>
  revert-claude-md <cwd>
  revert-settings-json <cwd>
  revert-gitattributes <cwd>
  revert-git-config <cwd>
  delete-merge-driver-script <cwd>
  delete-shared-dir <cwd>
  delete-git-branches <cwd> [merged-only|all]

Global reverts:
  delete-global-vault
  revert-global-claude-settings
  delete-plugin-data

Env:
  DRY_RUN=1                   Print what would happen, don't execute
USAGE
        exit 2
    fi
    shift

    case "$cmd" in
        preflight-check)         un_preflight_check "$@" ;;
        discover-project)        un_discover_project "$@" ;;
        discover-global)         un_discover_global "$@" ;;
        create-backup)           un_create_backup "$@" ;;
        delete-vault)            un_delete_vault "$@" ;;
        delete-sentinel-state)   un_delete_sentinel_state "$@" ;;
        revert-claude-md)        un_revert_claude_md "$@" ;;
        revert-settings-json)    un_revert_settings_json "$@" ;;
        revert-gitattributes)    un_revert_gitattributes "$@" ;;
        revert-git-config)       un_revert_git_config "$@" ;;
        delete-merge-driver-script) un_delete_merge_driver_script "$@" ;;
        delete-shared-dir)       un_delete_shared_dir "$@" ;;
        delete-git-branches)     un_delete_git_branches "$@" ;;
        delete-global-vault)     un_delete_global_vault "$@" ;;
        revert-global-claude-settings) un_revert_global_claude_settings "$@" ;;
        delete-plugin-data)      un_delete_plugin_data "$@" ;;
        *)
            echo "Unknown command: $cmd" >&2
            exit 2
            ;;
    esac
fi

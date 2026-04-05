#!/usr/bin/env bash
# Configure .claude/settings.json with allowedTools for the detected stack.
#
# Usage: configure-permissions.sh <project_dir> <stack> [preset]
#   stack: python | typescript | both | other
#   preset: power-user | standard (default: power-user)
#
# This script is called by the bootstrap command after stack detection.
# It writes to <project_dir>/.claude/settings.json, merging with existing settings.

set -euo pipefail

PROJECT_DIR="${1:-.}"
STACK="${2:-other}"
PRESET="${3:-power-user}"

SETTINGS_DIR="${PROJECT_DIR}/.claude"
SETTINGS_FILE="${SETTINGS_DIR}/settings.json"

mkdir -p "$SETTINGS_DIR"

# --- Permission definitions ---

# Common permissions (all stacks)
COMMON_PERMISSIONS=(
    # File operations
    "Bash(mkdir *)"
    "Bash(cp *)"
    "Bash(mv *)"
    "Bash(ls *)"
    "Bash(cat *)"
    "Bash(head *)"
    "Bash(tail *)"
    "Bash(wc *)"
    "Bash(chmod *)"
    # Git (non-destructive)
    "Bash(git status*)"
    "Bash(git diff*)"
    "Bash(git log*)"
    "Bash(git branch*)"
    "Bash(git show*)"
    "Bash(git stash*)"
    "Bash(git add *)"
    "Bash(git commit *)"
    "Bash(git checkout -b *)"
    "Bash(git switch -c *)"
    "Bash(git merge *)"
    "Bash(git rebase *)"
    "Bash(git cherry-pick *)"
    "Bash(git fetch*)"
    "Bash(git pull*)"
    "Bash(git remote -v*)"
    "Bash(git rev-parse *)"
    "Bash(git config *)"
    # Search
    "Bash(find *)"
    "Bash(grep *)"
    "Bash(rg *)"
    "Bash(ag *)"
    # Process inspection
    "Bash(which *)"
    "Bash(whoami*)"
    "Bash(pwd*)"
    "Bash(env *)"
    "Bash(echo *)"
    "Bash(date*)"
    # Network (read-only)
    "Bash(curl -s *)"
    "Bash(curl --silent *)"
    "Bash(wget -q *)"
)

PYTHON_PERMISSIONS=(
    # Virtual environment
    "Bash(*/.venv/bin/python *)"
    "Bash(*/.venv/bin/pip *)"
    "Bash(*/venv/bin/python *)"
    "Bash(*/venv/bin/pip *)"
    "Bash(python -m venv *)"
    "Bash(python3 -m venv *)"
    "Bash(pip install *)"
    "Bash(pip3 install *)"
    # Testing
    "Bash(*/.venv/bin/pytest *)"
    "Bash(*/venv/bin/pytest *)"
    "Bash(pytest *)"
    "Bash(python -m pytest *)"
    # Linting & formatting
    "Bash(*/.venv/bin/ruff *)"
    "Bash(*/venv/bin/ruff *)"
    "Bash(ruff check *)"
    "Bash(ruff format *)"
    "Bash(black *)"
    "Bash(isort *)"
    "Bash(flake8 *)"
    # Type checking
    "Bash(*/.venv/bin/mypy *)"
    "Bash(*/venv/bin/mypy *)"
    "Bash(mypy *)"
    "Bash(pyright *)"
    # Package management
    "Bash(pip freeze*)"
    "Bash(pip list*)"
    "Bash(pip show *)"
    "Bash(poetry *)"
    "Bash(pdm *)"
    "Bash(uv *)"
    # Database
    "Bash(*/.venv/bin/alembic *)"
    "Bash(*/venv/bin/alembic *)"
    "Bash(alembic *)"
    # Run scripts
    "Bash(python *)"
    "Bash(python3 *)"
    "Bash(*/.venv/bin/python -c *)"
)

TYPESCRIPT_PERMISSIONS=(
    # Package managers
    "Bash(npm *)"
    "Bash(npx *)"
    "Bash(yarn *)"
    "Bash(pnpm *)"
    "Bash(bun *)"
    # Testing
    "Bash(jest *)"
    "Bash(vitest *)"
    "Bash(playwright *)"
    "Bash(cypress *)"
    # Linting & formatting
    "Bash(eslint *)"
    "Bash(prettier *)"
    "Bash(biome *)"
    # Type checking
    "Bash(tsc *)"
    "Bash(tsc --noEmit*)"
    # Build
    "Bash(next *)"
    "Bash(vite *)"
    "Bash(webpack *)"
    "Bash(esbuild *)"
    "Bash(turbo *)"
    # Runtime
    "Bash(node *)"
    "Bash(tsx *)"
    "Bash(ts-node *)"
    "Bash(deno *)"
)

# --- Build the permission list ---

PERMISSIONS=("${COMMON_PERMISSIONS[@]}")

case "$STACK" in
    python)
        PERMISSIONS+=("${PYTHON_PERMISSIONS[@]}")
        ;;
    typescript)
        PERMISSIONS+=("${TYPESCRIPT_PERMISSIONS[@]}")
        ;;
    both)
        PERMISSIONS+=("${PYTHON_PERMISSIONS[@]}")
        PERMISSIONS+=("${TYPESCRIPT_PERMISSIONS[@]}")
        ;;
    other)
        # Include both for maximum coverage
        PERMISSIONS+=("${PYTHON_PERMISSIONS[@]}")
        PERMISSIONS+=("${TYPESCRIPT_PERMISSIONS[@]}")
        ;;
esac

# --- Build JSON ---

# Convert array to JSON array
PERMISSIONS_JSON="["
FIRST=true
for perm in "${PERMISSIONS[@]}"; do
    if [ "$FIRST" = true ]; then
        FIRST=false
    else
        PERMISSIONS_JSON+=","
    fi
    PERMISSIONS_JSON+="\"${perm}\""
done
PERMISSIONS_JSON+="]"

# Merge with existing settings or create new
if [ -f "$SETTINGS_FILE" ]; then
    # Merge: add new permissions to existing allowedTools array
    EXISTING=$(cat "$SETTINGS_FILE")
    MERGED=$(echo "$EXISTING" | jq --argjson perms "$PERMISSIONS_JSON" '
        .permissions.allow = ((.permissions.allow // []) + $perms | unique)
    ')
    echo "$MERGED" > "$SETTINGS_FILE"
else
    # Create new settings file
    jq -n --argjson perms "$PERMISSIONS_JSON" '{
        permissions: {
            allow: $perms
        }
    }' > "$SETTINGS_FILE"
fi

# Count permissions added
COUNT=$(echo "$PERMISSIONS_JSON" | jq 'length')
echo "$COUNT"

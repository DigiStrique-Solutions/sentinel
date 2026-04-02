#!/bin/bash
# STOP HOOK: Enforce vault maintenance before session ends
#
# At session end, checks whether the agent completed housekeeping tasks:
# 1. Changelog entry for today (if files were modified)
# 2. Investigation file (if failures were detected in transcript)
# 3. Open investigations reminder
# 4. Test file reminder (adversarial evaluation)
#
# Outputs warnings as a checklist. Does NOT block (exit 0) in v0.1 —
# just warns. This can be upgraded to exit 2 for blocking enforcement.
#
# Also cleans up .sentinel/ tracking directory and old session recovery files.

set -euo pipefail

INPUT=$(cat)
CWD=$(echo "$INPUT" | jq -r '.cwd // empty')
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty')
STOP_HOOK_ACTIVE=$(echo "$INPUT" | jq -r '.stop_hook_active // false')
TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.transcript_path // empty')

VAULT_DIR="${CWD}/vault"

# Graceful exit if vault doesn't exist
if [ ! -d "$VAULT_DIR" ]; then
    exit 0
fi

# Prevent infinite loop — if stop hook already fired once, let it through
if [ "$STOP_HOOK_ACTIVE" = "true" ]; then
    exit 0
fi

TODAY=$(date +%Y-%m-%d)
WARNINGS=""

# --- 1. Check if code files were modified this session ---
SENTINEL_DIR="${CWD}/.sentinel"
if [ -n "$SESSION_ID" ]; then
    SHORT_ID="${SESSION_ID:0:12}"
    SENTINEL_DIR="${CWD}/.sentinel/sessions/${SHORT_ID}"
fi
MODIFIED_FILE="${SENTINEL_DIR}/modified-files.txt"
FILES_CHANGED=""
FILE_COUNT=0

if [ -f "$MODIFIED_FILE" ]; then
    FILES_CHANGED=$(grep -E '\.(py|tsx?|jsx?|go|rs|rb|java|swift|kt|css|scss|sh)$' "$MODIFIED_FILE" | head -5 || echo "")
    FILE_COUNT=$(wc -l < "$MODIFIED_FILE" | tr -d ' ')
fi

# Trivial session escape hatch: 0-2 files modified skips changelog enforcement
SKIP_CHANGELOG=false
if [ "$FILE_COUNT" -le 2 ]; then
    SKIP_CHANGELOG=true
fi

if [ -n "$FILES_CHANGED" ] && [ "$SKIP_CHANGELOG" = "false" ]; then
    # Check for today's changelog entry
    if [ -d "${VAULT_DIR}/changelog" ]; then
        CHANGELOG_EXISTS=$(find "${VAULT_DIR}/changelog" -name "${TODAY}*" -type f 2>/dev/null | head -1)
        if [ -z "$CHANGELOG_EXISTS" ]; then
            WARNINGS="${WARNINGS}\n- [ ] NO CHANGELOG for today (${TODAY}). Files were modified — create a changelog entry."
        fi
    fi
fi

# --- 2. Check transcript for failure patterns ---
if [ -n "$TRANSCRIPT_PATH" ] && [ -f "$TRANSCRIPT_PATH" ]; then
    FAILURE_SIGNALS=$(tail -100 "$TRANSCRIPT_PATH" | grep -ciE "(failed|error|doesn.t work|broke|regression|rollback)" 2>/dev/null; true)
    if [ "$FAILURE_SIGNALS" -gt 3 ]; then
        # Check if there's a recent investigation file
        RECENT_INVESTIGATION=$(find "${VAULT_DIR}/investigations" -name "20*" -mmin -60 -type f 2>/dev/null | head -1)
        if [ -z "$RECENT_INVESTIGATION" ]; then
            WARNINGS="${WARNINGS}\n- [ ] Multiple failure signals detected but NO investigation logged. Create vault/investigations/ entry."
        fi
    fi
fi

# --- 3. Remind about open investigations ---
if [ -d "${VAULT_DIR}/investigations" ]; then
    OPEN_COUNT=0
    for f in "${VAULT_DIR}/investigations"/*.md; do
        [ -f "$f" ] || continue
        [ "$(basename "$f")" = "_template.md" ] && continue
        if ! grep -qi "status:.*\(resolved\|implemented\|obsolete\)" "$f" 2>/dev/null; then
            OPEN_COUNT=$((OPEN_COUNT + 1))
        fi
    done
    if [ "$OPEN_COUNT" -gt 0 ]; then
        WARNINGS="${WARNINGS}\n- [ ] ${OPEN_COUNT} open investigation(s) in vault/investigations/ — update status if any were resolved this session."
    fi
fi

# --- 4. Check if test files were written — remind about adversarial eval ---
if [ -f "$MODIFIED_FILE" ]; then
    TEST_FILES=$(grep -cE '(test_|_test\.|\.test\.|\.spec\.)' "$MODIFIED_FILE" 2>/dev/null; true)
    if [ "$TEST_FILES" -gt 0 ]; then
        WARNINGS="${WARNINGS}\n- [ ] ${TEST_FILES} test file(s) written — consider adversarial evaluation to verify test quality."
    fi
fi

# --- 4b. Documentation drift detection ---
# When source files were modified, check if architecture docs reference deleted/moved files
if [ -n "$FILES_CHANGED" ]; then
    PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"
    DRIFT_SCRIPT="${PLUGIN_ROOT}/scripts/detect-drift.sh"
    if [ -x "$DRIFT_SCRIPT" ]; then
        DRIFT_OUTPUT=$("$DRIFT_SCRIPT" "$CWD" "$MODIFIED_FILE" 2>/dev/null || echo "")
        if [ -n "$DRIFT_OUTPUT" ]; then
            WARNINGS="${WARNINGS}\n\n**DOCUMENTATION DRIFT DETECTED** — architecture docs reference files that changed or no longer exist:\n${DRIFT_OUTPUT}\n- [ ] Update the stale architecture docs listed above to reflect current code."
        fi
    fi
fi

# --- 5. Todo completeness audit ---
# If Claude used TodoWrite, check that all items are completed.
# This catches "all done!" when task Z was never touched.
TODO_FILE="${SENTINEL_DIR}/todos.json"
if [ -f "$TODO_FILE" ]; then
    # Count pending and in_progress items
    PENDING=$(jq '[.todos[] | select(.status == "pending")] | length' "$TODO_FILE" 2>/dev/null; true)
    IN_PROGRESS=$(jq '[.todos[] | select(.status == "in_progress")] | length' "$TODO_FILE" 2>/dev/null; true)
    INCOMPLETE=$((PENDING + IN_PROGRESS))

    if [ "$INCOMPLETE" -gt 0 ]; then
        # List the incomplete items
        INCOMPLETE_LIST=$(jq -r '.todos[] | select(.status != "completed") | "    - [\(.status)] \(.content)"' "$TODO_FILE" 2>/dev/null || echo "")
        WARNINGS="${WARNINGS}\n\n**INCOMPLETE TASKS** — ${INCOMPLETE} task(s) not marked as completed:\n${INCOMPLETE_LIST}\n- [ ] Complete all tasks before ending the session, or explicitly tell the user which tasks remain."
    fi
fi

# --- 6. Evidence-based verification audit ---
# Check the evidence log for required verification commands.
# If source files were modified but tests/lint were never run, flag it.
EVIDENCE_FILE="${SENTINEL_DIR}/evidence.log"
if [ -n "$FILES_CHANGED" ] && [ "$FILE_COUNT" -gt 0 ]; then
    # Determine what types of source files were modified
    HAS_PYTHON=$(grep -cE '\.py$' "$MODIFIED_FILE" 2>/dev/null; true)
    HAS_JS_TS=$(grep -cE '\.(tsx?|jsx?)$' "$MODIFIED_FILE" 2>/dev/null; true)

    if [ -f "$EVIDENCE_FILE" ]; then
        # Check for test execution
        TEST_RUNS=$(grep -c '|test:' "$EVIDENCE_FILE" 2>/dev/null; true)
        TEST_PASSES=$(grep -c '|test:.*|pass|' "$EVIDENCE_FILE" 2>/dev/null; true)
        TEST_FAILS=$(grep '|test:.*|fail' "$EVIDENCE_FILE" 2>/dev/null | tail -1 || echo "")

        # Check for lint execution
        LINT_RUNS=$(grep -c '|lint:' "$EVIDENCE_FILE" 2>/dev/null; true)
        LINT_FAILS=$(grep '|lint:.*|fail' "$EVIDENCE_FILE" 2>/dev/null | tail -1 || echo "")

        # Check for type checking
        TYPE_RUNS=$(grep -c '|typecheck|' "$EVIDENCE_FILE" 2>/dev/null; true)

        # --- Test verification ---
        if [ "$TEST_RUNS" -eq 0 ]; then
            WARNINGS="${WARNINGS}\n- [ ] **TESTS NEVER RAN** — ${FILE_COUNT} file(s) modified but no test command found in evidence log."
        elif [ -n "$TEST_FAILS" ]; then
            FAIL_TIME=$(echo "$TEST_FAILS" | cut -d'|' -f1)
            # Check if there's a passing test AFTER the last failure
            LAST_FAIL_LINE=$(grep -n '|test:.*|fail' "$EVIDENCE_FILE" 2>/dev/null | tail -1 | cut -d: -f1 || true)
            LAST_PASS_LINE=$(grep -n '|test:.*|pass' "$EVIDENCE_FILE" 2>/dev/null | tail -1 | cut -d: -f1 || true)
            if [ -z "$LAST_PASS_LINE" ] || [ "${LAST_PASS_LINE:-0}" -lt "${LAST_FAIL_LINE:-0}" ]; then
                WARNINGS="${WARNINGS}\n- [ ] **TESTS FAILED** — Last test run at ${FAIL_TIME} ended with failure. No subsequent passing run found."
            fi
        fi

        # --- Lint verification ---
        if [ "$HAS_PYTHON" -gt 0 ] && ! grep -q '|lint:python|' "$EVIDENCE_FILE" 2>/dev/null; then
            WARNINGS="${WARNINGS}\n- [ ] **PYTHON LINTER NEVER RAN** — ${HAS_PYTHON} Python file(s) modified but no ruff/pylint/flake8 found in evidence log."
        fi
        if [ "$HAS_JS_TS" -gt 0 ] && ! grep -q '|lint:js|' "$EVIDENCE_FILE" 2>/dev/null; then
            WARNINGS="${WARNINGS}\n- [ ] **JS/TS LINTER NEVER RAN** — ${HAS_JS_TS} JS/TS file(s) modified but no eslint/lint command found in evidence log."
        fi

        # --- Lint failure check ---
        if [ -n "$LINT_FAILS" ]; then
            LINT_FAIL_TIME=$(echo "$LINT_FAILS" | cut -d'|' -f1)
            LAST_LINT_FAIL=$(grep -n '|lint:.*|fail' "$EVIDENCE_FILE" 2>/dev/null | tail -1 | cut -d: -f1 || true)
            LAST_LINT_PASS=$(grep -n '|lint:.*|pass' "$EVIDENCE_FILE" 2>/dev/null | tail -1 | cut -d: -f1 || true)
            if [ -z "$LAST_LINT_PASS" ] || [ "${LAST_LINT_PASS:-0}" -lt "${LAST_LINT_FAIL:-0}" ]; then
                WARNINGS="${WARNINGS}\n- [ ] **LINT FAILED** — Last lint at ${LINT_FAIL_TIME} ended with failure. No subsequent passing run found."
            fi
        fi

        # --- Type check for TypeScript ---
        if [ "$HAS_JS_TS" -gt 0 ] && [ "$TYPE_RUNS" -eq 0 ]; then
            WARNINGS="${WARNINGS}\n- [ ] **TYPE CHECK NEVER RAN** — ${HAS_JS_TS} TS/JS file(s) modified but no tsc found in evidence log."
        fi
    else
        # No evidence file at all — no verification commands were run
        if [ "$FILE_COUNT" -gt 2 ]; then
            WARNINGS="${WARNINGS}\n- [ ] **NO VERIFICATION COMMANDS RUN** — ${FILE_COUNT} file(s) modified but no tests, lint, or type checks found in the session."
        fi
    fi
fi

# --- 6b. RED-GREEN-BREADTH verification pattern ---
# For bug fixes, check that: (1) a test failed BEFORE the first edit (reproduce),
# (2) tests passed after the fix, (3) test scope was broad enough.
# This catches the #1 verification gap: narrow fix + narrow test = "done" but user finds new bugs.
BUGFIX_MODE_FILE="${SENTINEL_DIR}/mode-bugfix"
if [ -f "$EVIDENCE_FILE" ] && [ -n "$FILES_CHANGED" ]; then
    # Check test BREADTH — narrow test scope is a warning
    # Narrow: only ran a single test file/function (e.g., pytest tests/test_one.py::test_specific)
    # Broad: ran a directory or module (e.g., pytest tests/, yarn test)
    NARROW_TESTS=0
    BROAD_TESTS=0
    while IFS= read -r line; do
        CMD=$(echo "$line" | cut -d'|' -f4)
        # Narrow: contains :: (pytest specific test) or ends with a specific test file
        if echo "$CMD" | grep -qE '::|--grep|--filter|-t [^ ]+$'; then
            NARROW_TESTS=$((NARROW_TESTS + 1))
        else
            BROAD_TESTS=$((BROAD_TESTS + 1))
        fi
    done < <(grep '|test:.*|pass' "$EVIDENCE_FILE" 2>/dev/null || true)

    if [ "$NARROW_TESTS" -gt 0 ] && [ "$BROAD_TESTS" -eq 0 ] && [ "$FILE_COUNT" -gt 1 ]; then
        WARNINGS="${WARNINGS}\n- [ ] **NARROW TEST SCOPE** — Only targeted tests were run. Consider running the full test suite to catch regressions in adjacent code."
    fi

    # Bug-fix mode: check for RED-GREEN pattern (reproduce-first)
    if [ -f "$BUGFIX_MODE_FILE" ]; then
        # Check if a test FAILED before the first source edit
        FIRST_EDIT_TIME=""
        if [ -f "$MODIFIED_FILE" ]; then
            # Get the modification time of the tracking file (proxy for first edit)
            if [[ "$OSTYPE" == "darwin"* ]]; then
                FIRST_EDIT_TIME=$(stat -f %m "$MODIFIED_FILE" 2>/dev/null || echo "")
            else
                FIRST_EDIT_TIME=$(stat -c %Y "$MODIFIED_FILE" 2>/dev/null || echo "")
            fi
        fi

        # Check for RED phase: any test failure in the evidence log
        FIRST_FAIL_LINE=$(grep -n '|test:.*|fail' "$EVIDENCE_FILE" 2>/dev/null | head -1 | cut -d: -f1 || true)
        FIRST_PASS_LINE=$(grep -n '|test:.*|pass' "$EVIDENCE_FILE" 2>/dev/null | head -1 | cut -d: -f1 || true)

        if [ -z "$FIRST_FAIL_LINE" ]; then
            WARNINGS="${WARNINGS}\n- [ ] **NO REPRODUCE STEP** — This appears to be a bug fix, but no failing test was recorded before the fix. Consider reproducing the bug with a failing test first."
        elif [ -n "$FIRST_PASS_LINE" ] && [ "${FIRST_FAIL_LINE:-999}" -gt "${FIRST_PASS_LINE:-0}" ]; then
            # First test was a pass, fail came later — might be normal TDD, not a concern
            :
        fi
    fi

    # Check for IMPACTED tests that were not run
    IMPACT_FILE="${SENTINEL_DIR}/impact-tests.txt"
    if [ -f "$IMPACT_FILE" ]; then
        UNRUN_IMPACTS=""
        while IFS= read -r impact_test; do
            [ -z "$impact_test" ] && continue
            # Check if this test file appears in any evidence log test command
            if ! grep -q "$(basename "$impact_test")" "$EVIDENCE_FILE" 2>/dev/null; then
                UNRUN_IMPACTS="${UNRUN_IMPACTS}\n    - ${impact_test}"
            fi
        done < "$IMPACT_FILE"
        if [ -n "$UNRUN_IMPACTS" ]; then
            WARNINGS="${WARNINGS}\n- [ ] **IMPACTED TESTS NOT RUN** — These test files import modified code but were not executed:${UNRUN_IMPACTS}"
        fi
    fi
fi

# --- 7. Clean up old session recovery files ---
if [ -d "${VAULT_DIR}/session-recovery" ]; then
    # Compaction recovery files: delete after 4 hours
    find "${VAULT_DIR}/session-recovery" -name "20*-*.md" ! -name "summary-*" -mmin +240 -type f -delete 2>/dev/null || true
    # Session summaries: delete after 48 hours
    find "${VAULT_DIR}/session-recovery" -name "summary-*.md" -mmin +2880 -type f -delete 2>/dev/null || true
fi

# --- Output warnings ---
if [ -n "$WARNINGS" ]; then
    # Log quality gate warnings to activity feed
    PLUGIN_LOGGER="$(dirname "$0")/activity-logger.sh"
    if [ -f "$PLUGIN_LOGGER" ]; then
        REPO_ROOT="$CWD" source "$PLUGIN_LOGGER"
        # Count the number of warnings
        WARN_COUNT=$(echo -e "$WARNINGS" | grep -c '^\- \[' 2>/dev/null; true)
        log_activity "Quality gate warnings: ${WARN_COUNT} issue(s) flagged at session end"
    fi

    echo -e "VAULT MAINTENANCE CHECKLIST -- please address before stopping:\n${WARNINGS}"
fi

# Auto-move resolved investigations to resolved/ subdirectory
# This enables the pruner to archive them after 30 days
if [ -d "${CWD}/vault/investigations" ]; then
    for f in "${CWD}/vault/investigations"/*.md; do
        [ -f "$f" ] || continue
        [ "$(basename "$f")" = "_template.md" ] && continue
        if grep -qi "status:.*\(resolved\|implemented\|obsolete\)" "$f" 2>/dev/null; then
            mkdir -p "${CWD}/vault/investigations/resolved" 2>/dev/null || true
            mv "$f" "${CWD}/vault/investigations/resolved/" 2>/dev/null || true
        fi
    done
fi

# --- Collect session stats before cleanup ---
# Append one session record to vault/.sentinel-stats.json for /sentinel stats
if [ -n "$SESSION_ID" ] && [ -d "$VAULT_DIR" ]; then
    STATS_FILE="${VAULT_DIR}/.sentinel-stats.json"
    TODAY=$(date +%Y-%m-%d)

    # Gather metrics from session data (before it's cleaned up)
    STATS_TESTS_RUN="false"
    STATS_TESTS_PASSED="false"
    STATS_LINT_RUN="false"
    STATS_LINT_PASSED="false"
    STATS_GOTCHA_HITS=0
    STATS_INVESTIGATIONS_LOADED=0
    STATS_INVESTIGATION_RESOLVED="false"

    if [ -f "$EVIDENCE_FILE" ]; then
        grep -q '|test:' "$EVIDENCE_FILE" 2>/dev/null && STATS_TESTS_RUN="true"
        # Last test entry is a pass
        LAST_TEST=$(grep '|test:' "$EVIDENCE_FILE" 2>/dev/null | tail -1 || true)
        if echo "$LAST_TEST" | grep -q '|pass' 2>/dev/null; then
            STATS_TESTS_PASSED="true"
        fi
        grep -q '|lint:' "$EVIDENCE_FILE" 2>/dev/null && STATS_LINT_RUN="true"
        LAST_LINT=$(grep '|lint:' "$EVIDENCE_FILE" 2>/dev/null | tail -1 || true)
        if echo "$LAST_LINT" | grep -q '|pass' 2>/dev/null; then
            STATS_LINT_PASSED="true"
        fi
    fi

    GOTCHA_HITS_FILE="${SENTINEL_DIR}/gotcha-hits.txt"
    if [ -f "$GOTCHA_HITS_FILE" ]; then
        STATS_GOTCHA_HITS=$(awk '{s+=$1} END {print s+0}' "$GOTCHA_HITS_FILE" 2>/dev/null || echo "0")
    fi

    INVESTIGATIONS_LOADED_FILE="${CWD}/.sentinel/investigations-loaded.txt"
    if [ -f "$INVESTIGATIONS_LOADED_FILE" ]; then
        STATS_INVESTIGATIONS_LOADED=$(wc -l < "$INVESTIGATIONS_LOADED_FILE" | tr -d ' ')
    fi

    # Check if any investigation was resolved this session
    if [ -d "${VAULT_DIR}/investigations/resolved" ]; then
        # Were any resolved files modified in the last few minutes? (proxy for "resolved this session")
        RECENTLY_RESOLVED=$(find "${VAULT_DIR}/investigations/resolved" -name "*.md" -mmin -5 -type f 2>/dev/null | wc -l | tr -d ' ')
        if [ "$RECENTLY_RESOLVED" -gt 0 ]; then
            STATS_INVESTIGATION_RESOLVED="true"
        fi
    fi

    # Build JSON record and append
    STATS_RECORD=$(jq -n \
        --arg date "$TODAY" \
        --arg sid "$SHORT_ID" \
        --argjson files "$FILE_COUNT" \
        --argjson tests_run "$STATS_TESTS_RUN" \
        --argjson tests_passed "$STATS_TESTS_PASSED" \
        --argjson lint_run "$STATS_LINT_RUN" \
        --argjson lint_passed "$STATS_LINT_PASSED" \
        --argjson gotcha_hits "$STATS_GOTCHA_HITS" \
        --argjson investigations_loaded "$STATS_INVESTIGATIONS_LOADED" \
        --argjson investigation_resolved "$STATS_INVESTIGATION_RESOLVED" \
        '{date: $date, session_id: $sid, files_modified: $files, tests_run: $tests_run, tests_passed: $tests_passed, lint_run: $lint_run, lint_passed: $lint_passed, gotcha_hits: $gotcha_hits, investigations_loaded: $investigations_loaded, investigation_resolved: $investigation_resolved}' 2>/dev/null)

    if [ -n "$STATS_RECORD" ]; then
        if [ -f "$STATS_FILE" ]; then
            # Append to existing array
            jq --argjson rec "$STATS_RECORD" '.sessions += [$rec]' "$STATS_FILE" > "${STATS_FILE}.tmp" 2>/dev/null && mv "${STATS_FILE}.tmp" "$STATS_FILE" || true
        else
            # Create new file
            echo "{\"sessions\": [${STATS_RECORD}]}" | jq '.' > "$STATS_FILE" 2>/dev/null || true
        fi
    fi
fi

# Clean up session-scoped sentinel tracking
if [ -n "$SESSION_ID" ]; then
    rm -rf "${CWD}/.sentinel/sessions/${SHORT_ID}" 2>/dev/null || true
    # Note: do NOT delete ${SHORT_ID}.json here — stop-merge.sh owns that lifecycle
else
    # Legacy: no session_id, clean up flat .sentinel/
    rm -f "${CWD}/.sentinel/modified-files.txt" "${CWD}/.sentinel/scope-warned" 2>/dev/null || true
fi

# v0.1: warn only, don't block
exit 0

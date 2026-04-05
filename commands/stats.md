---
name: sentinel-stats
description: Show Sentinel effectiveness metrics — vault health, knowledge reuse, and code discipline over time.
---

# Stats Command

Show how Sentinel is performing. Read vault data and session history to produce a formatted report.

**Usage:** `/sentinel-stats [--period 7d|30d|90d] [--json]`

Default period: 30 days. Use `--json` for machine-readable output.

## Step 1: Parse Arguments

Extract from the user's message:
- **period**: Time window — `7d`, `30d` (default), or `90d`
- **json**: If present, output raw JSON instead of formatted text

## Step 2: Gather Vault Health Data

Count files in each vault directory. Use `find` and frontmatter parsing.

```bash
# Investigations
OPEN_COUNT=$(find vault/investigations/ -maxdepth 1 -name "*.md" ! -name "_template.md" -type f 2>/dev/null | wc -l | tr -d ' ')
RESOLVED_COUNT=$(find vault/investigations/resolved/ -name "*.md" -type f 2>/dev/null | wc -l | tr -d ' ')
ARCHIVED_COUNT=$(find vault/.archive/investigations/ -name "*.md" -type f 2>/dev/null | wc -l | tr -d ' ')
TOTAL_INVESTIGATIONS=$((OPEN_COUNT + RESOLVED_COUNT + ARCHIVED_COUNT))
RESOLUTION_RATE=0
if [ "$TOTAL_INVESTIGATIONS" -gt 0 ]; then
    RESOLUTION_RATE=$(( (RESOLVED_COUNT + ARCHIVED_COUNT) * 100 / TOTAL_INVESTIGATIONS ))
fi

# Gotchas
GOTCHA_COUNT=$(find vault/gotchas/ -name "*.md" ! -name "_template.md" ! -name "_example.md" -type f 2>/dev/null | wc -l | tr -d ' ')

# Decisions
DECISION_TOTAL=$(find vault/decisions/ -name "*.md" ! -name "_template.md" -type f 2>/dev/null | wc -l | tr -d ' ')
DECISION_SUPERSEDED=$(grep -rl "status:.*superseded" vault/decisions/ 2>/dev/null | wc -l | tr -d ' ')
DECISION_ACTIVE=$((DECISION_TOTAL - DECISION_SUPERSEDED))

# Patterns
PATTERN_COUNT=$(find vault/patterns/learned/ -name "*.md" -type f 2>/dev/null | wc -l | tr -d ' ')
```

Count gotchas added/removed in the period using git log:
```bash
GOTCHAS_ADDED=$(git log --since="30 days ago" --diff-filter=A --name-only --pretty=format: -- vault/gotchas/ 2>/dev/null | grep -c "\.md$" || echo "0")
GOTCHAS_REMOVED=$(git log --since="30 days ago" --diff-filter=D --name-only --pretty=format: -- vault/gotchas/ 2>/dev/null | grep -c "\.md$" || echo "0")
```

## Step 3: Gather Knowledge Reuse Data

Read from `vault/.sentinel-stats.json` if it exists. Filter by the period.

```bash
STATS_FILE="vault/.sentinel-stats.json"
if [ -f "$STATS_FILE" ]; then
    CUTOFF_DATE=$(date -v-30d +%Y-%m-%d 2>/dev/null || date -d "30 days ago" +%Y-%m-%d)

    # Total sessions in period
    SESSIONS_IN_PERIOD=$(jq --arg cutoff "$CUTOFF_DATE" '[.sessions[] | select(.date >= $cutoff)] | length' "$STATS_FILE")

    # Gotcha hits
    TOTAL_GOTCHA_HITS=$(jq --arg cutoff "$CUTOFF_DATE" '[.sessions[] | select(.date >= $cutoff) | .gotcha_hits] | add // 0' "$STATS_FILE")
    SESSIONS_WITH_GOTCHAS=$(jq --arg cutoff "$CUTOFF_DATE" '[.sessions[] | select(.date >= $cutoff and .gotcha_hits > 0)] | length' "$STATS_FILE")

    # Investigation loads
    TOTAL_INVESTIGATIONS_LOADED=$(jq --arg cutoff "$CUTOFF_DATE" '[.sessions[] | select(.date >= $cutoff) | .investigations_loaded] | add // 0' "$STATS_FILE")
    INVESTIGATIONS_LED_TO_RESOLUTION=$(jq --arg cutoff "$CUTOFF_DATE" '[.sessions[] | select(.date >= $cutoff and .investigation_resolved == true)] | length' "$STATS_FILE")
fi
```

## Step 4: Gather Code Discipline Data

From `vault/.sentinel-stats.json`:

```bash
SESSIONS_WITH_TESTS=$(jq --arg cutoff "$CUTOFF_DATE" '[.sessions[] | select(.date >= $cutoff and .tests_run == true)] | length' "$STATS_FILE")
SESSIONS_TESTS_PASSED=$(jq --arg cutoff "$CUTOFF_DATE" '[.sessions[] | select(.date >= $cutoff and .tests_passed == true)] | length' "$STATS_FILE")
SESSIONS_WITH_LINT=$(jq --arg cutoff "$CUTOFF_DATE" '[.sessions[] | select(.date >= $cutoff and .lint_run == true)] | length' "$STATS_FILE")
```

From git log (conventional commits in the period):

```bash
FEAT_COMMITS=$(git log --since="30 days ago" --oneline 2>/dev/null | grep -c "^[a-f0-9]* feat:" || echo "0")
FIX_COMMITS=$(git log --since="30 days ago" --oneline 2>/dev/null | grep -c "^[a-f0-9]* fix:" || echo "0")
REFACTOR_COMMITS=$(git log --since="30 days ago" --oneline 2>/dev/null | grep -c "^[a-f0-9]* refactor:" || echo "0")
TEST_COMMITS=$(git log --since="30 days ago" --oneline 2>/dev/null | grep -c "^[a-f0-9]* test:" || echo "0")
CHORE_COMMITS=$(git log --since="30 days ago" --oneline 2>/dev/null | grep -c "^[a-f0-9]* chore:" || echo "0")
DOCS_COMMITS=$(git log --since="30 days ago" --oneline 2>/dev/null | grep -c "^[a-f0-9]* docs:" || echo "0")
```

Compute fix ratio:
```bash
FIX_RATIO="N/A"
if [ "$FEAT_COMMITS" -gt 0 ]; then
    # Use awk for decimal division
    FIX_RATIO=$(awk "BEGIN {printf \"%.2f\", $FIX_COMMITS / $FEAT_COMMITS}")
fi
```

## Step 5: Output Formatted Report

Print the report using this exact format:

```
Sentinel Stats — <project_name>
══════════════════════════════════

Vault Health
  Investigations:  <resolved+archived> resolved, <open> open  (<rate>% resolution rate)
  Gotchas:         <count> documented  (<added> added, <removed> removed in <period>)
  Decisions:       <active> accepted, <superseded> superseded
  Patterns:        <count> learned

Knowledge Reuse (last <period>)
  Gotchas surfaced before edits:    <hits> times across <sessions> sessions
  Investigations loaded at start:   <loaded> times  (<resolved_count> led to resolution)

Code Discipline (last <period>)
  Sessions tracked:    <total>
  Tests run:           <with_tests> / <total> sessions  (<pct>%)
  Tests passed:        <passed> / <with_tests> runs     (<pct>%)
  Lint run:            <with_lint> / <total> sessions    (<pct>%)
  Commits:  <feat> feat, <fix> fix, <refactor> refactor, <test> test, <chore> chore
  Fix ratio:           <ratio> fixes per feature  (lower is better)
```

If `vault/.sentinel-stats.json` doesn't exist, show the Vault Health section (always available from vault files) and note:

```
Knowledge Reuse & Code Discipline data will appear after a few sessions.
Session data is collected automatically by Sentinel hooks.
```

## Step 6: JSON Output (if --json)

If the user passed `--json`, output the raw data as JSON instead of the formatted report:

```json
{
  "period": "30d",
  "vault_health": {
    "investigations_open": 2,
    "investigations_resolved": 25,
    "investigations_archived": 10,
    "resolution_rate_pct": 93,
    "gotchas": 11,
    "gotchas_added": 3,
    "gotchas_removed": 1,
    "decisions_active": 6,
    "decisions_superseded": 0,
    "patterns_learned": 0
  },
  "knowledge_reuse": {
    "gotcha_hits": 14,
    "gotcha_sessions": 8,
    "investigations_loaded": 6,
    "investigations_resolved": 4
  },
  "code_discipline": {
    "sessions_total": 23,
    "tests_run": 21,
    "tests_passed": 19,
    "lint_run": 18,
    "commits": {"feat": 12, "fix": 8, "refactor": 15, "test": 9, "chore": 11, "docs": 2},
    "fix_ratio": 0.67
  }
}
```

## Key Rules

1. **Show what happened, not what was prevented.** "Gotchas surfaced 14 times" is honest. "14 bugs prevented" is a claim.
2. **All counts must come from actual data.** Never estimate or extrapolate.
3. **Graceful degradation.** If stats.json doesn't exist, show vault health only. If git isn't available, skip commit data. Never error.
4. **Period filtering.** Only count sessions within the requested period. Vault health counts are always lifetime (not period-filtered).

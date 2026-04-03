---
name: sentinel prune
description: Deep vault cleanup — find duplicates, validate cross-references, archive stale entries, and report vault health. Run monthly or before major feature pushes.
---

# Vault Deep Prune

Run a comprehensive vault cleanup. This is Tier 3 pruning — deeper than the automatic session-start pruning.

## Steps

1. **Read vault structure** — scan all directories under `vault/` and count entries per category
2. **Run the prune script** for a baseline report:
   ```bash
   "${CLAUDE_PLUGIN_ROOT}/scripts/vault-prune.sh" vault/
   ```

3. **Duplicate detection** — search for vault entries with similar titles or overlapping content:
   - Check `vault/gotchas/` for entries describing the same constraint
   - Check `vault/investigations/` for entries about the same problem area
   - Check `vault/decisions/` for entries that contradict each other

4. **Cross-reference validation** — for each gotcha and decision:
   - Extract file paths mentioned in the entry
   - Check if those files still exist in the project
   - If ALL referenced files are gone, flag the entry

5. **Archive stale entries** — move to `vault/.archive/` (preserving directory structure):
   - Resolved investigations older than 30 days
   - Changelog entries older than 90 days
   - Superseded/deprecated decisions
   - Gotchas where all referenced files are deleted (ask user first)
   - Session recovery files older than 7 days

6. **Pattern health** — check `vault/patterns/learned/`:
   - List patterns by confidence score
   - Flag patterns with 0 observations
   - Flag patterns older than 30 days with confidence < 0.5

7. **Size report** — output a summary table:

   ```
   | Category        | Count | Stale | Archived |
   |-----------------|-------|-------|----------|
   | investigations  |    12 |     2 |        3 |
   | gotchas         |     8 |     1 |        0 |
   | decisions       |     5 |     0 |        1 |
   | patterns        |     3 |     1 |        0 |
   | workflows       |    13 |     0 |        0 |
   | changelog       |    20 |     5 |        5 |
   | session-recovery|     2 |     0 |        2 |
   | .archive        |    11 |     — |        — |
   ```

8. **Archive cleanup** — if `vault/.archive/` has entries older than 180 days, ask the user if they want to permanently delete them

## Key Rules

- **Archive, never delete** — all moves go to `vault/.archive/` preserving directory structure
- **Ask before archiving gotchas** — the conceptual lesson might still apply even if files changed
- **Show what was archived** — output a list of every file moved so nothing disappears silently
- **Permanent deletion only with explicit user approval** — for .archive entries >180 days old

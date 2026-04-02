# Vault Maintenance Workflow

The vault is only useful if it's accurate. Stale information is worse than no information -- it actively misleads future sessions. This workflow defines when and how to maintain the vault.

## When to Write to the Vault

### Immediately (during work)

**Failed attempt -> Investigation journal:**
When a fix attempt fails for a non-obvious reason, create or update a file in `vault/investigations/`:
1. Copy `vault/investigations/_template.md`
2. Name it descriptively: `YYYY-MM-<brief-slug>.md`
3. Log each attempt with hypothesis, what was tried, and why it failed
4. This prevents the SAME failed approach from being tried in the next session

**Non-obvious discovery -> Gotcha:**
When you discover something unexpected about the codebase (a hidden constraint, an undocumented dependency, a "this looks like it should work but doesn't because..."), immediately add it to `vault/gotchas/`.

### After completing work

**Architectural decision -> ADR:**
If the fix/feature required choosing between approaches, document why in `vault/decisions/NNN-slug.md`.

**Significant work -> Completed entry:**
For features, migrations, or multi-file changes, add to `vault/completed/`.

**Investigation resolved -> Update status:**
If the work resolves an open investigation, update its status to `resolved` and fill in the root cause + fix sections.

## Staleness Protocol

After completing any task that changes the codebase, check if existing vault entries are now wrong:

### 1. Check gotchas
```
Read vault/gotchas/ filenames. For each one related to the area you just changed:
- Is this gotcha still true?
- Did your fix eliminate the underlying issue?
- If the gotcha is now wrong, DELETE the file or update it.
```

### 2. Check decisions
```
Read vault/decisions/ filenames. For each one related to the area you just changed:
- Is this decision still in effect?
- Did your change supersede it?
- If superseded, update status to "Superseded by ADR-NNN" and add the new ADR.
```

### 3. Check investigations
```
Read vault/investigations/ filenames. For each open investigation:
- Does your fix resolve it?
- If yes, update status to "resolved" and fill in the root cause.
- If your fix makes an attempt in the journal irrelevant, note that.
```

### 4. Check completed entries
```
If your work makes a previous "Remaining Work" section obsolete, update it.
```

## Example: Self-Healing in Action

**Session 1:** User reports API responses returning stale data.
1. Claude reads `vault/gotchas/` -- nothing relevant
2. Claude tries adding cache invalidation headers -> fails (issue is server-side)
3. Claude creates `vault/investigations/2026-03-stale-api-responses.md`:
   - Attempt 1: Cache headers. Failed because the caching is server-side, not browser.
4. Claude discovers the real issue: database read replica lag
5. Claude fixes it, updates investigation status to "resolved"
6. Claude adds `vault/gotchas/read-replica-lag.md`

**Session 2:** Different user hits similar stale data issue.
1. Claude reads `vault/gotchas/read-replica-lag.md` -- knows the root cause
2. Claude reads the investigation -- knows cache headers don't work
3. Claude goes straight to the correct fix

**Session 3:** User migrates to a single-node database.
1. Claude completes the migration
2. **Staleness check:** `vault/gotchas/read-replica-lag.md` -- is this still true?
3. No -- there's no read replica anymore. Claude deletes the gotcha.
4. Claude adds a new ADR documenting the database architecture change

## Rules

1. **Never leave stale information.** Wrong information in the vault will actively hurt future sessions. If something changed, update or delete the vault entry.
2. **Write immediately, not at the end.** If a fix attempt fails, document it NOW, not after 3 more attempts.
3. **Investigation files are append-only during debugging.** Never delete attempt entries -- they record what NOT to try.
4. **Gotcha files can be deleted.** If the underlying issue is fixed, the gotcha is noise. Delete it.
5. **ADRs are never deleted, only superseded.** Change status to "Superseded by ADR-NNN".

#workflow #vault-maintenance

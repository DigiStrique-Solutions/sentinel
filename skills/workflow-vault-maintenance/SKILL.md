---
name: sentinel-workflow-vault-maintenance
description: Vault hygiene meta-workflow — check gotchas, decisions, investigations, and completed entries for staleness after any codebase change. Use whenever updating the vault after completing a task, OR when another workflow invokes it as a sub-step for vault healing. Also triggered when the user says "vault hygiene", "clean the vault", "stale entries", "prune investigations", "update gotchas", "heal the vault", or otherwise asks for vault maintenance. The Iron Law of this workflow is: STALE INFORMATION IS WORSE THAN NO INFORMATION. Four steps — check gotchas, check decisions, check investigations, check completed.
workflow: true
workflow-steps: 4
allowed-tools: Read Grep Glob Bash Edit Write MultiEdit TodoWrite
origin: sentinel
---

# Vault Maintenance Workflow

> **Meta-workflow note:** This is a meta-workflow about vault hygiene, not a task-driven process. Other workflows (bug-fix, new-feature, refactor, etc.) invoke it as a sub-step under "Document & Heal the Vault" for their staleness check. It can also be run directly any time you need to audit the vault after a change.

The vault is only useful if it's accurate. Stale information is worse than no information -- it actively misleads future sessions. This workflow defines when and how to maintain the vault.

This is a Sentinel workflow skill. When it activates, the `sentinel-workflow-runner` protocol drives execution — creates a run directory, checkpoints progress after each step, and supports resumption across sessions. You do not need to invoke the runner explicitly; it activates alongside this skill.

## Protocol summary

At the top of the workflow, create a new run:

```bash
RUN_ID=$(bash "${CLAUDE_PLUGIN_ROOT}/scripts/workflow-state.sh" start vault-maintenance)
```

Before each numbered step, call `step-start`. After each step completes, call `step-complete` (with an artifact path if you produced one). After the final step, call `finish <run-id> completed`. On failure, call `step-fail` and follow the failure-handling rules in each section below.

Full protocol details: see `sentinel-workflow-runner` skill.

---

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

## 1. Check gotchas

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/workflow-state.sh" step-start "$RUN_ID" 1 "Check gotchas"
```

```
Read vault/gotchas/ filenames. For each one related to the area you just changed:
- Is this gotcha still true?
- Did your fix eliminate the underlying issue?
- If the gotcha is now wrong, DELETE the file or update it.
```

**Write an artifact**: `vault/workflows/runs/$RUN_ID/artifacts/step-1-gotchas.md` listing each gotcha reviewed and its action (kept / updated / deleted).

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/workflow-state.sh" step-complete "$RUN_ID" 1 "artifacts/step-1-gotchas.md"
```

## 2. Check decisions

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/workflow-state.sh" step-start "$RUN_ID" 2 "Check decisions"
```

```
Read vault/decisions/ filenames. For each one related to the area you just changed:
- Is this decision still in effect?
- Did your change supersede it?
- If superseded, update status to "Superseded by ADR-NNN" and add the new ADR.
```

**Write an artifact**: `artifacts/step-2-decisions.md` listing each decision reviewed and its action (kept / superseded / new ADR).

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/workflow-state.sh" step-complete "$RUN_ID" 2 "artifacts/step-2-decisions.md"
```

## 3. Check investigations

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/workflow-state.sh" step-start "$RUN_ID" 3 "Check investigations"
```

```
Read vault/investigations/ filenames. For each open investigation:
- Does your fix resolve it?
- If yes, update status to "resolved" and fill in the root cause.
- If your fix makes an attempt in the journal irrelevant, note that.
```

**Write an artifact**: `artifacts/step-3-investigations.md` listing each investigation reviewed and its action (kept open / resolved / annotated).

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/workflow-state.sh" step-complete "$RUN_ID" 3 "artifacts/step-3-investigations.md"
```

## 4. Check completed entries

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/workflow-state.sh" step-start "$RUN_ID" 4 "Check completed entries"
```

```
If your work makes a previous "Remaining Work" section obsolete, update it.
```

**Write an artifact**: `artifacts/step-4-completed.md` listing each completed entry touched and the updates made.

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/workflow-state.sh" step-complete "$RUN_ID" 4 "artifacts/step-4-completed.md"
bash "${CLAUDE_PLUGIN_ROOT}/scripts/workflow-state.sh" finish "$RUN_ID" completed
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

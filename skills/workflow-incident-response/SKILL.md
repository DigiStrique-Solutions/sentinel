---
name: sentinel-workflow-incident-response
description: Production incident workflow — triage, diagnose, decide rollback vs forward fix, fix, verify, post-incident. Use whenever the user says "prod is down", "production issue", "incident", "outage", "users reporting", "P0", "P1", "site is broken", "500 errors in prod", "rollback", "hotfix", or otherwise signals a live production problem — even if they don't explicitly say "workflow". Prioritizes speed over perfection for P0/P1, mandates an investigation file even for obvious fixes, and always requires a regression test. Six steps — triage, diagnose, rollback-or-forward, fix, verify, post-incident.
workflow: true
workflow-steps: 6
allowed-tools: Read Grep Glob Bash Edit Write MultiEdit TodoWrite
origin: sentinel
---

# Incident Response Workflow

For production issues affecting users. Different from bug-fix -- you can't always reproduce locally, and speed matters.

This is a Sentinel workflow skill. When it activates, the `sentinel-workflow-runner` protocol drives execution — creates a run directory, checkpoints progress after each step, and supports resumption across sessions. You do not need to invoke the runner explicitly; it activates alongside this skill.

## Protocol summary

At the top of the workflow, create a new run:

```bash
RUN_ID=$(bash "${CLAUDE_PLUGIN_ROOT}/scripts/workflow-state.sh" start incident-response)
```

Before each numbered step, call `step-start`. After each step completes, call `step-complete` (with an artifact path if you produced one). After the final step, call `finish <run-id> completed`. On failure, call `step-fail` and follow the failure-handling rules in each section below.

Full protocol details: see `sentinel-workflow-runner` skill.

---

## Severity Classification

| Severity | Criteria | Response time |
|----------|----------|---------------|
| **P0 -- Critical** | App unusable, data loss, auth broken | Immediate |
| **P1 -- High** | Major feature broken, significant user impact | Within hours |
| **P2 -- Medium** | Feature degraded, workaround exists | Within 1 day |
| **P3 -- Low** | Minor UX issue, cosmetic | Next sprint |

## 1. Triage (5 minutes max)

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/workflow-state.sh" step-start "$RUN_ID" 1 "Triage"
```

- [ ] Classify severity (P0-P3)
- [ ] Identify affected area (backend, frontend, database, external API)
- [ ] Check `vault/investigations/` -- has this happened before?
- [ ] Check `vault/gotchas/` -- is there a known pitfall?
- [ ] Determine blast radius: how many users affected?

**Write an artifact**: `vault/workflows/runs/$RUN_ID/artifacts/step-1-triage.md` recording the severity, affected area, blast radius, and any relevant vault matches.

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/workflow-state.sh" step-complete "$RUN_ID" 1 "artifacts/step-1-triage.md"
```

## 2. Diagnose

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/workflow-state.sh" step-start "$RUN_ID" 2 "Diagnose"
```

### Server-side issues:
- [ ] Check application logs for errors
- [ ] Query the database for affected records
- [ ] Check if external services are reachable

### Frontend issues:
- [ ] Check browser console for errors
- [ ] Check network tab for failed requests
- [ ] Verify the backend is reachable (health endpoint)

### External API issues:
- [ ] Check if the third-party API is down (status pages)
- [ ] Check for token expiry or rate limiting
- [ ] Check for API version deprecation

**Write an artifact**: `artifacts/step-2-diagnose.md` with log excerpts, failed request details, and the working hypothesis for the root cause.

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/workflow-state.sh" step-complete "$RUN_ID" 2 "artifacts/step-2-diagnose.md"
```

## 3. Decide: Rollback or Forward Fix

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/workflow-state.sh" step-start "$RUN_ID" 3 "Rollback or Forward Fix"
```

### Rollback if:
- The issue was introduced by a recent deployment
- The fix is not obvious
- P0 severity -- users are blocked NOW
- `git log --oneline -10` shows the likely culprit

### Forward fix if:
- Root cause is clear and fix is small
- Rollback would lose other important changes
- The issue is a data/configuration problem, not a code problem

**Write an artifact**: `artifacts/step-3-decision.md` recording the decision (rollback vs forward fix) and the reasoning.

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/workflow-state.sh" step-complete "$RUN_ID" 3 "artifacts/step-3-decision.md"
```

## 4. Fix

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/workflow-state.sh" step-start "$RUN_ID" 4 "Fix"
```

- [ ] Write a failing test that reproduces the issue (if possible)
- [ ] Make the minimal fix
- [ ] Run the failing test -- confirm it passes
- [ ] Run the full test suite for the affected module

### If you can't reproduce locally:
- [ ] Add targeted logging to narrow the issue
- [ ] Check database state for inconsistencies
- [ ] Check if the issue is timing-dependent or load-dependent

**Write an artifact**: `artifacts/step-4-fix.md` with the test (or logging strategy if no reproduction), the fix, and test output.

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/workflow-state.sh" step-complete "$RUN_ID" 4 "artifacts/step-4-fix.md"
```

## 5. Verify

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/workflow-state.sh" step-start "$RUN_ID" 5 "Verify"
```

- [ ] Fix resolves the reported issue
- [ ] No regression in related functionality
- [ ] Tests pass
- [ ] If P0/P1: verify in production after deploy

**Write an artifact**: `artifacts/step-5-verify.md` with test output, production verification notes (if applicable), and confirmation the original report is resolved.

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/workflow-state.sh" step-complete "$RUN_ID" 5 "artifacts/step-5-verify.md"
```

## 6. Post-Incident

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/workflow-state.sh" step-start "$RUN_ID" 6 "Post-Incident"
```

- [ ] Create `vault/investigations/YYYY-MM-<slug>.md` with:
  - What happened
  - Root cause
  - What was tried
  - What fixed it
  - How to prevent recurrence
- [ ] Add to `vault/gotchas/` if the root cause is a non-obvious constraint
- [ ] Update `vault/changelog/` with the fix
- [ ] If a monitoring gap was exposed, note what alerting would have caught this earlier

**Write an artifact**: `artifacts/step-6-post-incident.md` linking to the investigation file and listing any gotchas/changelog/monitoring notes created.

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/workflow-state.sh" step-complete "$RUN_ID" 6 "artifacts/step-6-post-incident.md"
bash "${CLAUDE_PLUGIN_ROOT}/scripts/workflow-state.sh" finish "$RUN_ID" completed
```

## Key Rules

- **Speed over perfection for P0/P1.** Ship the fix, then clean up.
- **Always create an investigation file.** Even if the fix was obvious -- the next person needs context.
- **Never fix production issues without a test.** If you can't write a test before the fix, write one immediately after.
- **Check the gotchas first.** Many "new" production issues are actually known pitfalls.

#workflow #incident #production

# Incident Response Workflow

For production issues affecting users. Different from bug-fix -- you can't always reproduce locally, and speed matters.

## Severity Classification

| Severity | Criteria | Response time |
|----------|----------|---------------|
| **P0 -- Critical** | App unusable, data loss, auth broken | Immediate |
| **P1 -- High** | Major feature broken, significant user impact | Within hours |
| **P2 -- Medium** | Feature degraded, workaround exists | Within 1 day |
| **P3 -- Low** | Minor UX issue, cosmetic | Next sprint |

## 1. Triage (5 minutes max)

- [ ] Classify severity (P0-P3)
- [ ] Identify affected area (backend, frontend, database, external API)
- [ ] Check `vault/investigations/` -- has this happened before?
- [ ] Check `vault/gotchas/` -- is there a known pitfall?
- [ ] Determine blast radius: how many users affected?

## 2. Diagnose

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

## 3. Decide: Rollback or Forward Fix

### Rollback if:
- The issue was introduced by a recent deployment
- The fix is not obvious
- P0 severity -- users are blocked NOW
- `git log --oneline -10` shows the likely culprit

### Forward fix if:
- Root cause is clear and fix is small
- Rollback would lose other important changes
- The issue is a data/configuration problem, not a code problem

## 4. Fix

- [ ] Write a failing test that reproduces the issue (if possible)
- [ ] Make the minimal fix
- [ ] Run the failing test -- confirm it passes
- [ ] Run the full test suite for the affected module

### If you can't reproduce locally:
- [ ] Add targeted logging to narrow the issue
- [ ] Check database state for inconsistencies
- [ ] Check if the issue is timing-dependent or load-dependent

## 5. Verify

- [ ] Fix resolves the reported issue
- [ ] No regression in related functionality
- [ ] Tests pass
- [ ] If P0/P1: verify in production after deploy

## 6. Post-Incident

- [ ] Create `vault/investigations/YYYY-MM-<slug>.md` with:
  - What happened
  - Root cause
  - What was tried
  - What fixed it
  - How to prevent recurrence
- [ ] Add to `vault/gotchas/` if the root cause is a non-obvious constraint
- [ ] Update `vault/changelog/` with the fix
- [ ] If a monitoring gap was exposed, note what alerting would have caught this earlier

## Key Rules

- **Speed over perfection for P0/P1.** Ship the fix, then clean up.
- **Always create an investigation file.** Even if the fix was obvious -- the next person needs context.
- **Never fix production issues without a test.** If you can't write a test before the fix, write one immediately after.
- **Check the gotchas first.** Many "new" production issues are actually known pitfalls.

#workflow #incident #production

---
name: sentinel-verification-before-completion
description: Use BEFORE claiming work is done, fixed, passing, complete, or ready to commit/PR. Forbids success claims without fresh verification evidence captured in the current message. Activates whenever you are about to say tests pass, build succeeds, the bug is fixed, the regression test works, or the implementation is done.
origin: sentinel
---

# Verification Before Completion

Stop claiming work is done. Run the command. Read the output. Then claim it — with the evidence cited inline.

## The Iron Law

> **Never claim success without fresh verification evidence captured in this same message.**

If you have not run the verification command since you last edited the relevant code, you cannot say "the tests pass," "the build succeeds," "the bug is fixed," or any synonym thereof. The previous run does not count. The agent's "I made the change" does not count. Reading the code and concluding "this looks right" does not count.

Only the command output, fresh, with exit code visible, counts.

## Why this exists

Claude — and humans — both fall into the same failure mode: writing the change, looking at the code, deciding it ought to work, and announcing victory. The diff looks right. The logic checks out. So the test must pass, right?

Often it does. Sometimes it doesn't. The 1-in-5 case where you announce success and you're wrong is what destroys trust. The user later runs the command, sees a failure, and now everything else you said is suspect.

Cheap insurance: run the command before you speak.

## The gate function

Before you write the words "passes," "fixed," "done," "ready," "complete," "good to go," or anything similar, walk this gate:

1. **Identify** — what one command proves the claim?
2. **Run** — execute the full command, fresh, in this message
3. **Read** — full output. Check the exit code. Count failures explicitly.
4. **Decide** — does the output actually confirm the claim?
   - If no → state the actual status, with the failing line cited
   - If yes → state the claim, with the passing line cited
5. **Then speak** — never before

Skipping any step is not "saving time." It is lying with extra steps.

## Claim → required evidence table

| Claim | Evidence that satisfies the Iron Law | Evidence that does NOT |
|---|---|---|
| Tests pass | Test runner output: `N passed, 0 failed`, exit 0 | "Should pass," "I ran it earlier," "the linter is happy" |
| Linter clean | Linter output: `0 errors` | Tests passing, code reviewed |
| Build succeeds | Build command exits 0 | Linter passing, type-check passing |
| Bug fixed | Test of the original failure mode now passes | Code changed, "this should fix it" |
| Regression test works | RED → GREEN cycle observed in this message | Test passes once after the fix |
| Subagent finished task | `git diff` showing the change + tests passing | Subagent's "done" message |
| Requirements met | Line-by-line walk through spec, with each item ticked off against evidence | "I addressed everything" |

## Forbidden phrasings (without inline evidence)

These are red flags. If you find yourself typing one, stop and run something:

- "Should work now"
- "I think this is done"
- "Looks good to me"
- "Probably passing"
- "Seems to be working"
- "Great!" / "Perfect!" / "All good!" / "Done!" — any celebratory wrap-up phrase before evidence
- "Just to be safe, let me commit this" — committing is a claim of completeness

## Common rationalizations and rebuttals

| Rationalization | Reality |
|---|---|
| "I'm confident in the change" | Confidence is not evidence. Run the command. |
| "Just this once, the diff is obviously correct" | The "obvious" cases are exactly where unverified claims slip through. Run it. |
| "The linter passed, so the build will pass" | Linter is not a compiler. Run the build. |
| "The agent reported success" | Agents lie cheerfully. Run the verification yourself. |
| "I'm out of context budget" | Not running the command does not save tokens — it costs trust. Run it. |
| "I already ran it two messages ago" | You edited code since then. Run it again. |

## What "fresh in this message" means

The verification command must appear in the current assistant turn — typically as a Bash tool call whose output is visible above the claim. If the verification was in a previous turn, and you have edited code since, it is stale.

If the verification was in a previous turn AND you have not edited any relevant code since, you may reference it explicitly: "Verified in the previous turn (link/timestamp) — no relevant code has changed." But the safe default is to re-run.

## Integration with other Sentinel skills

- **sentinel-tdd** — RED/GREEN/REFACTOR's GREEN step is a verification claim. The Iron Law applies.
- **sentinel-workflow-bug-fix** — the "verify" step in the bug-fix workflow is governed by this skill.
- **sentinel-subagent-driven-development** — when a subagent reports task completion, the orchestrator MUST verify independently before marking the task done. The subagent's report is not evidence.
- **sentinel-finishing-a-development-branch** — before announcing the branch is ready, the full verification command set must run fresh.

## Example

❌ **Wrong:**
> I've fixed the failing test by handling the null case. The implementation looks correct — should be passing now. Let me commit this.

✅ **Right:**
> I've fixed the failing test by handling the null case. Running the test:
>
> ```
> $ pytest tests/test_user.py -v
> tests/test_user.py::test_null_user PASSED
> tests/test_user.py::test_normal_user PASSED
> ============== 2 passed in 0.31s ==============
> ```
>
> Both tests pass. Committing.

The difference is one Bash call. That's the entire cost.

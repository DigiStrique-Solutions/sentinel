---
name: sentinel-workflow-feature-improvement
description: Disciplined workflow for improving an existing feature — understand current behavior, define the change, update tests, implement, verify, document. Use whenever the user says "improve", "enhance", "extend", "add a filter", "add a column", "better error messages", "tweak", "polish", or otherwise asks to modify working code without adding a whole new feature and without fixing a bug — even if they don't explicitly say "workflow". The key risk this workflow manages is *breaking existing behavior*, so backward compatibility is treated as a first-class concern. Six steps — understand, define, write/update tests, implement, verify, document.
workflow: true
workflow-steps: 6
allowed-tools: Read Grep Glob Bash Edit Write MultiEdit TodoWrite
origin: sentinel
---

# Feature Improvement Workflow

Improving an existing feature -- not building from scratch (use `sentinel-workflow-new-feature`) and not fixing a bug (use `sentinel-workflow-bug-fix`). You're modifying working code to make it better.

This is a Sentinel workflow skill. When it activates, the `sentinel-workflow-runner` protocol drives execution — creates a run directory, checkpoints progress after each step, and supports resumption across sessions. You do not need to invoke the runner explicitly; it activates alongside this skill.

## Protocol summary

At the top of the workflow, create a new run:

```bash
RUN_ID=$(bash "${CLAUDE_PLUGIN_ROOT}/scripts/workflow-state.sh" start feature-improvement)
```

Before each numbered step, call `step-start`. After each step completes, call `step-complete` (with an artifact path if you produced one). After the final step, call `finish <run-id> completed`. On failure, call `step-fail` and follow the failure-handling rules in each section below.

Full protocol details: see `sentinel-workflow-runner` skill.

---

## Examples

- Adding a filter to an existing list view
- Improving error messages in an existing flow
- Adding a new column to an existing table
- Enhancing an existing API endpoint with new parameters
- Improving UX of an existing feature (loading states, feedback, copy)

## 1. Understand Current Behavior

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/workflow-state.sh" step-start "$RUN_ID" 1 "Understand Current Behavior"
```

- [ ] Read the existing implementation completely (not just the area you're changing)
- [ ] Read existing tests to understand expected behavior
- [ ] Read relevant architecture docs in `vault/architecture/`
- [ ] Check `vault/gotchas/` for pitfalls in this area
- [ ] Check `vault/decisions/` for why the current implementation exists
- [ ] **Check `vault/investigations/` for past debugging** -- the improvement might re-introduce a previously fixed issue

**Write an artifact**: `vault/workflows/runs/$RUN_ID/artifacts/step-1-understand.md` summarizing current behavior, existing tests, and any relevant vault context.

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/workflow-state.sh" step-complete "$RUN_ID" 1 "artifacts/step-1-understand.md"
```

## 2. Define the Improvement

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/workflow-state.sh" step-start "$RUN_ID" 2 "Define the Improvement"
```

- [ ] What specific behavior changes? (be precise -- "better" is not a spec)
- [ ] What stays the same? (explicitly list preserved behaviors)
- [ ] Are there backward compatibility concerns? (existing API consumers, stored data)
- [ ] Does this change the API contract? (if yes, consider versioning or migration)

**Write an artifact**: `artifacts/step-2-define.md` with a precise spec of what changes, what stays the same, and backward-compat implications.

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/workflow-state.sh" step-complete "$RUN_ID" 2 "artifacts/step-2-define.md"
```

## 3. Write / Update Tests (RED)

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/workflow-state.sh" step-start "$RUN_ID" 3 "Write or Update Tests"
```

- [ ] Write new tests for the NEW behavior
- [ ] Verify existing tests still describe the PRESERVED behavior
- [ ] If existing tests need updating (because behavior intentionally changed), update them
- [ ] Run all tests -- new tests should **fail**, existing tests should **pass**
- [ ] Follow test standards in `vault/quality/test-standards.md`

**Write an artifact**: `artifacts/step-3-tests.md` listing each new/updated test, its file path, and the initial pass/fail state.

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/workflow-state.sh" step-complete "$RUN_ID" 3 "artifacts/step-3-tests.md"
```

## 4. Implement (GREEN)

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/workflow-state.sh" step-start "$RUN_ID" 4 "Implement"
```

- [ ] Make the minimal changes needed for the improvement
- [ ] Follow existing patterns -- don't introduce new patterns for one change
- [ ] Don't refactor surrounding code (that's a separate task -- see `sentinel-workflow-refactor`)
- [ ] Read `vault/quality/anti-patterns.md` -- use none of the listed patterns
- [ ] Run tests -- all should **pass** (new + existing)

### If the improvement changes API behavior:
- [ ] Update contract tests if endpoint signature changed
- [ ] Update API clients on the consumer side
- [ ] Verify backward compatibility (old clients still work)

**Write an artifact**: `artifacts/step-4-implement.md` describing the change made and the final test run output.

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/workflow-state.sh" step-complete "$RUN_ID" 4 "artifacts/step-4-implement.md"
```

## 5. Verify

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/workflow-state.sh" step-start "$RUN_ID" 5 "Verify"
```

- [ ] All tests pass (new + existing + unrelated)
- [ ] Read `vault/quality/gates.md` -- pass all gates
- [ ] Run linter

**Write an artifact**: `artifacts/step-5-verify.md` with each quality gate and its pass/fail status.

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/workflow-state.sh" step-complete "$RUN_ID" 5 "artifacts/step-5-verify.md"
```

## 6. Document

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/workflow-state.sh" step-start "$RUN_ID" 6 "Document"
```

- [ ] If the improvement changes how things work, update `vault/architecture/`
- [ ] If backward compatibility was a consideration, add to `vault/decisions/`
- [ ] If a non-obvious constraint was discovered, add to `vault/gotchas/`
- [ ] **Staleness check:** did this improvement make any existing gotchas or decisions obsolete?
- [ ] Commit with appropriate prefix: `feat:` (new capability) or `fix:` (improved existing)

**Write an artifact**: `artifacts/step-6-document.md` listing all vault entries touched (created, updated, deleted).

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/workflow-state.sh" step-complete "$RUN_ID" 6 "artifacts/step-6-document.md"
bash "${CLAUDE_PLUGIN_ROOT}/scripts/workflow-state.sh" finish "$RUN_ID" completed
```

## Key Differences from New Feature

| | New Feature | Feature Improvement |
|---|---|---|
| Starting point | Nothing exists | Working code exists |
| Tests | All new | Mix of new + updated existing |
| Backward compat | Not a concern | Must preserve unless explicitly breaking |
| Scope risk | Over-building | Breaking existing behavior |
| Refactoring | Part of the process | Separate task, not mixed in |

#workflow #feature #improvement

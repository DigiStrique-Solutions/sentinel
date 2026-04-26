---
name: sentinel-writing-plans
description: Use AFTER brainstorming has produced an approved spec, BEFORE writing any implementation code. Decomposes a spec into bite-sized 2-5 minute tasks with exact file paths, test code, verification steps, and checkbox tracking. Saves to vault/planning/. Activates when the user says "write a plan", "plan this out", "break this into tasks", "create a TodoWrite for this", or after sentinel-brainstorm has handed off.
origin: sentinel
---

# Writing Plans

Turn an approved spec into an implementation plan that another engineer (or another Claude session) can execute task-by-task without ever asking you a question.

## The non-negotiable

> **A plan that requires the executor to make architectural decisions is not a plan — it's a spec.**

If a task in your plan has a sentence like "figure out the right place for this" or "decide whether to use X or Y," it belongs in the spec, not the plan. Resolve it before writing the plan, or send it back to brainstorming.

## Where this skill fits

```
sentinel-brainstorm → vault/planning/<topic>-spec.md (approved by user)
        ↓
sentinel-writing-plans → vault/planning/<topic>-plan.md
        ↓
sentinel-executing-plans  OR  sentinel-subagent-driven-development
```

Do not invoke this skill until the spec exists and the user has approved it. If a user says "plan X" without a spec, run sentinel-brainstorm first.

## Output location

`vault/planning/YYYY-MM-DD-<feature-name>-plan.md`

Save the file before reporting completion. The plan is a deliverable, not a chat artifact.

## Plan header (every plan starts with this)

```markdown
# <Feature Name> Implementation Plan

> **Executor:** Use sentinel-subagent-driven-development if subagents are available, otherwise sentinel-executing-plans. Tasks use checkbox syntax (`- [ ]`) for tracking.

**Spec:** vault/planning/YYYY-MM-DD-<feature-name>-spec.md
**Goal:** <one sentence>
**Architecture:** <2-3 sentences on the chosen approach>
**Tech stack:** <key libraries/frameworks>
**Council required:** <true | false>  (true if >5 files, ambiguous, or prior failed attempt)

---
```

The `Council required` flag is read by sentinel-plan-council later. Set true when the plan touches >5 files, when the spec resolved a tradeoff with low confidence, or when a previous attempt at this work failed.

## Bite-sized task granularity

Each task is one component, system, or vertical slice. Each step within a task is **one action, 2-5 minutes**. If a step takes longer than 5 minutes to execute, it's not a step — it's another task.

Good steps:
- "Write the failing test for null-input handling"
- "Run the test and confirm it fails with `AssertionError`"
- "Implement the null guard in `parse_input`"
- "Run the test and confirm it passes"
- "Run the surrounding test suite to confirm no regression"
- "Commit with message `fix: handle null input in parse_input`"

Bad steps:
- "Implement authentication" (too big — that's a task, not a step)
- "Make sure everything works" (not a discrete action)
- "Refactor the user module" (no clear done condition)

## Per-task structure

````markdown
### Task N: <component name>

**Files:**
- Create: `exact/path/to/new_file.py`
- Modify: `exact/path/to/existing_file.py:LINE-LINE`
- Test: `tests/exact/path/to/test_file.py`

**Verification:**
- Command: `pytest tests/exact/path/to/test_file.py -v`
- Expected: `2 passed in <Xs>`

**Steps:**

- [ ] **1. Write the failing test**

  ```python
  def test_specific_behavior():
      result = function(input_value)
      assert result == expected_value
  ```

- [ ] **2. Run the test, confirm it fails**

  Expected output: `AssertionError` or `ImportError`. The test must fail for the right reason — if it errors before reaching the assertion, the test setup is wrong.

- [ ] **3. Implement the minimal code to pass**

  ```python
  def function(input_value):
      if input_value is None:
          return default_value
      return process(input_value)
  ```

- [ ] **4. Run the test, confirm it passes**

  Expected output: `1 passed in <Xs>`.

- [ ] **5. Run surrounding suite, confirm no regression**

  `pytest tests/exact/path/to/ -v`

- [ ] **6. Commit**

  Message: `feat(area): brief description`
````

The point is: the executor reads each step and *does that one thing*. No deciding. No interpreting. If they had to interpret, the plan was incomplete.

## File structure decisions go in the plan, not the spec

Before writing tasks, the plan must answer:
- Which files will be created?
- Which files will be modified?
- What is each file responsible for?

These decisions are part of *implementation*, not *design*. They belong in the plan, where they are visible and reviewable. A common failure mode: the spec says "add user auth," the plan jumps straight to tasks, and three tasks in the executor realizes there's no obvious place to put the session token logic. That's a plan failure, not a spec failure.

Show the file map up front:

```markdown
## File Layout

| File | New/Modified | Responsibility |
|---|---|---|
| `src/auth/session.py` | New | Session token issuance + verification |
| `src/auth/middleware.py` | New | Request authentication middleware |
| `src/api/users.py` | Modify | Wire middleware onto user routes |
| `tests/auth/test_session.py` | New | Unit tests for session module |
| `tests/auth/test_middleware.py` | New | Unit tests for middleware |
| `tests/api/test_users.py` | Modify | Update for auth header requirement |
```

## Self-review before saving

Before writing the plan to disk, walk this checklist:

- [ ] Every task has exact file paths
- [ ] Every task has a verification command and expected output
- [ ] No step contains the words "figure out," "decide," or "investigate"
- [ ] No step takes longer than 5 minutes to execute
- [ ] No step depends on the executor having context you didn't write down
- [ ] The file layout section maps every change
- [ ] If the plan touches >5 files, the `Council required` header flag is set to true
- [ ] All assumptions from the spec are restated, not implied

If any item fails the checklist, fix it before saving.

## What to do when a task is genuinely ambiguous

Some tasks resist decomposition because the right approach depends on something you'll only learn during execution (e.g., "extract the right interface from this messy module"). Two options:

1. **Mark it as a research spike** — add a Task 0 that produces a written micro-decision before the implementation tasks. Save the decision to `vault/decisions/`.
2. **Stop and brainstorm** — if more than one task hits this wall, the spec is under-resolved. Send it back.

Never paper over ambiguity with a vague step. The whole point of a plan is to remove decisions from the executor.

## Integration

- **Inputs:** approved spec from sentinel-brainstorm
- **Outputs:** plan file at `vault/planning/<date>-<feature>-plan.md`
- **Next step:** invoke `sentinel-plan-execute` — that skill handles the council gate and routes to the right executor (subagent-driven-development or executing-plans). Don't pick the executor manually from this skill; let plan-execute do that decision once.
- **Council trigger:** the `Council required` header field in the plan, plus the auto-trigger heuristic in `scripts/plan-needs-council.sh` (>5 files). Both are checked by plan-execute, not by this skill.

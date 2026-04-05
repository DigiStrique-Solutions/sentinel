---
name: sentinel-adversarial-eval
description: Adversarial evaluation protocol for finding flaws in tests, prompts, and code reviews. Activates when validating test quality, auditing prompts, reviewing architecture, or running convergence loops. Enforces multi-round evaluation with 3-round max, mutation testing concepts, and structured issue tracking.
origin: sentinel
---

# Adversarial Evaluation

A protocol for systematically finding flaws in work products (tests, prompts, code reviews, architecture documents) through structured adversarial review. The core insight: the person who writes code is poorly positioned to find its flaws. A separate evaluator with an adversarial mindset catches what the author misses.

## When to Activate

- Validating that tests actually test what they claim to test
- Auditing agent prompts for gaps, contradictions, or missing instructions
- Reviewing architecture documents for completeness
- Running convergence loops on any work product that needs quality assurance
- After any round of test writing or prompt engineering

---

## 1. The Problem

Work products have predictable blind spots:

| Work Product | Common Blind Spot |
|-------------|-------------------|
| Tests | Test the mock instead of the code. Assert `is not None` instead of specific values. |
| Prompts | Missing negative instructions (what NOT to do). Contradictory rules. |
| Code reviews | Surface-level feedback. Missing security issues. Approving because "it works." |
| Architecture | Missing failure modes. Ignoring edge cases. Optimistic assumptions. |

A single pass by the author catches 60-70% of issues. Adversarial evaluation catches the rest.

---

## 2. The Convergence Protocol

### Overview

```
Agent A: Creates the work product (tests, prompt, code)
Agent B: Evaluates the work product adversarially (DIFFERENT session)
Agent A/C: Fixes the issues Agent B found
Agent B/D: Re-evaluates ONLY the fixes
Repeat until converged or 3 rounds reached
```

### Step 1: Initial Work (Agent A)

Agent A produces the work product and makes explicit claims:
- "I verified X, Y, Z"
- "Tests cover scenarios A, B, C"
- "Prompt handles cases 1, 2, 3"

These claims become the target for adversarial evaluation.

### Step 2: Adversarial Evaluation (Agent B)

Agent B's ONLY job is to find flaws. Agent B must:

1. **Use a different session** from Agent A (fresh context, no confirmation bias)
2. **Produce a numbered list of specific issues** -- not vague concerns
3. **For each issue, include:**
   - File and line number (or section reference)
   - What is wrong
   - Why it matters (impact)
   - How to fix it
4. **Classify severity:** CRITICAL, HIGH, MEDIUM, LOW
5. **Save results** to a structured file for tracking

```markdown
# Adversarial Eval: <Subject> - Round N

## Issues Found

### 1. [CRITICAL] Test `test_create_user` tests the mock, not the code
File: tests/test_users.py:42
Issue: The test mocks `UserService.create` and asserts the mock was called.
       If `UserService.create` is deleted, this test still passes.
Impact: Zero test coverage for user creation logic.
Fix: Remove the mock. Call the real `create_user()` with test inputs.
     Assert specific properties of the returned user object.

### 2. [HIGH] Missing error case for duplicate email
File: tests/test_users.py
Issue: No test for creating a user with an email that already exists.
Impact: Duplicate email handling is untested. Could silently overwrite users.
Fix: Add test_create_user_with_duplicate_email_raises_conflict_error.
```

### Step 3: Fix (Agent A or C)

Fix ONLY the issues Agent B found:
- Do not add new features
- Do not refactor unrelated code
- Produce a diff showing exactly what changed
- Map each change back to the issue number it resolves

### Step 4: Re-Evaluation (Agent B or D)

Re-evaluate ONLY the fixes:
- Are the original issues resolved?
- Did the fixes introduce new issues?
- Save as the next round's eval file

### Step 5: Convergence Check

```
Converged:
  - All issues from round N are resolved
  - Round N+1 found 0 new issues

Not converged:
  - Repeat steps 3-4

Max rounds reached (3):
  - Escalate to user with remaining issues list
```

---

## 3. Test Quality Checklist

For EACH test in the codebase, verify these six properties:

### DELETE TEST

> If I delete the implementation being tested, does this test fail?

If the test still passes after deleting the implementation, it is testing a mock, not real code. This is the most common and most dangerous test anti-pattern.

### WRONG OUTPUT

> If the function returns garbage data, does this test catch it?

A test that asserts `is not None` or `is True` will pass for almost any output. Tests must assert specific, meaningful values.

```python
# Fails the WRONG OUTPUT check -- passes for any non-None return
result = service.get_items(org_id)
assert result is not None

# Passes the WRONG OUTPUT check -- catches garbage data
result = service.get_items(org_id)
assert len(result) == 3
assert result[0].name == "Test Item"
assert result[0].status == "ACTIVE"
```

### NOT TESTING MOCKS

> Is the test exercising real code, or just verifying mock setup?

```python
# FAILS: tests the mock, not the classifier
classifier = MagicMock()
classifier.classify.return_value = Result(score=0.9)
result = classifier.classify("input")
assert result.score == 0.9  # Of course it is -- you told it to return 0.9

# PASSES: tests the real classifier
classifier = Classifier()
result = classifier.classify("multi-step complex query")
assert result.score > 0.7
assert result.needs_planning is True
```

### SPECIFIC ASSERTIONS

> Does the test assert specific, meaningful values -- not just existence?

```python
# VAGUE: passes for almost anything
assert response.status_code == 200
assert response.json() is not None

# SPECIFIC: verifies actual behavior
assert response.status_code == 200
assert response.json()["user"]["email"] == "test@example.com"
assert response.json()["user"]["role"] == "admin"
assert "password" not in response.json()["user"]
```

### EDGE CASES

> Are error conditions, boundary values, and invalid inputs tested?

Every function needs tests for:
- Empty inputs (empty string, empty list, None)
- Boundary values (zero, negative, maximum)
- Invalid inputs (wrong type, malformed data)
- Error conditions (network failure, permission denied, timeout)

### INDEPENDENCE

> Does this test depend on other tests running first?

Tests must not share mutable state. Each test should set up its own preconditions and clean up after itself. Tests should be runnable in any order, individually or in parallel.

---

## 4. Mutation Testing

### Concept

Mutation testing is the gold standard for test quality validation. The idea:

1. **Mutate the implementation** -- make a small, behavior-changing modification
2. **Run the tests** -- they should fail (they should detect the mutation)
3. **If tests still pass** -- the test suite has a gap (the mutation "survived")

### Types of Mutations

| Mutation | Example | What It Tests |
|----------|---------|---------------|
| Negate condition | `if x > 0` becomes `if x <= 0` | Branch coverage |
| Remove statement | Delete a function call | Side effect detection |
| Change operator | `+` becomes `-`, `==` becomes `!=` | Arithmetic/comparison logic |
| Return default | Return `None`/`[]`/`0` instead of computed value | Output verification |
| Swap arguments | `func(a, b)` becomes `func(b, a)` | Parameter order sensitivity |

### Interpreting Results

- **Mutation score = killed mutations / total mutations**
- **Score < 50%** -- tests are likely testing mocks or asserting nothing meaningful
- **Score 50-70%** -- partial coverage, significant gaps remain
- **Score 70-85%** -- good coverage, address remaining survivors
- **Score > 85%** -- strong test suite

### When to Use

- After writing a batch of tests (verify they actually work)
- Before declaring a module "well-tested"
- When a bug slips through tests that were supposed to catch it
- During adversarial eval rounds focused on test quality

---

## 5. Prompt Audit Convergence

### Round 1: Baseline Audit

For system prompts, agent prompts, or prompt templates:

1. Read the entire prompt
2. List all issues found:
   - Missing instructions (things the agent should do but is not told to)
   - Contradictory rules (two instructions that conflict)
   - Gaps in coverage (scenarios the prompt does not address)
   - Ambiguous language (instructions that could be interpreted multiple ways)
   - Missing negative examples (what the agent should NOT do)
3. Rate severity: CRITICAL / HIGH / MEDIUM / LOW
4. Save to eval tracking file

### Round 2: Fix and Re-Audit

1. Fix all CRITICAL and HIGH issues from Round 1
2. A DIFFERENT evaluator re-audits the prompt
3. The re-audit MUST reference Round 1's issue list
4. New issues get added; resolved issues get marked with a checkmark
5. Save as Round 2

### Round 3: Final Check (only if needed)

- Only run if Round 2 found new CRITICAL or HIGH issues
- Focus ONLY on unresolved items
- If no new CRITICAL/HIGH found, the prompt is converged

### Diminishing Returns

- Round 1 typically finds 60-70% of issues
- Round 2 finds 20-25% more
- Round 3 finds 5-10% more
- Beyond Round 3 = diminishing returns. Stop.

---

## 6. Architecture Review Convergence

Apply the same protocol to architecture documents and design decisions:

### What to Check

- **Missing failure modes** -- what happens when X goes down?
- **Optimistic assumptions** -- "the API will always respond in < 100ms"
- **Scaling blind spots** -- what happens at 10x, 100x current load?
- **Security gaps** -- who can access what? What are the trust boundaries?
- **Data consistency** -- what happens during partial failures?
- **Operational concerns** -- how is this monitored, debugged, deployed?

### Adversarial Questions

For each component in the architecture:
1. What is the worst thing that can happen?
2. What happens if this component is unavailable for 1 hour?
3. What data is lost if this crashes mid-operation?
4. Who has access to this, and should they?
5. How would I know if this is silently failing?

---

## 7. Tracking and File Structure

### Eval Tracking Files

```
vault/evals/
  YYYY-MM-DD-<subject>-round-1.md
  YYYY-MM-DD-<subject>-round-2.md
  YYYY-MM-DD-<subject>-round-3.md
  _convergence-log.md
```

### Convergence Log

Track which evaluations converged and which were escalated:

```markdown
# Convergence Log

| Date | Subject | Rounds | Result | Notes |
|------|---------|--------|--------|-------|
| 2026-03-16 | test-quality | 2 | Converged | All issues resolved in round 2 |
| 2026-03-18 | prompt-audit | 3 | Escalated | 1 CRITICAL remaining, needs user input |
| 2026-03-20 | arch-review | 2 | Converged | Added failure mode documentation |
```

---

## Key Principles

1. **The author cannot evaluate their own work.** Use a different session or agent for adversarial evaluation.
2. **Three rounds maximum.** Beyond three rounds, you hit diminishing returns. Escalate remaining issues to a human.
3. **Specific issues, not vague concerns.** "Tests could be better" is not actionable. "Test on line 42 asserts `is not None` instead of checking the actual email value" is.
4. **Fix only what was found.** During the fix step, address only the identified issues. Do not add features or refactor.
5. **Track convergence.** Without a log, you lose visibility into which areas have been evaluated and which have not.
6. **Mutation testing is the ultimate arbiter.** If you want to know whether tests are real, mutate the code and see if they catch it.

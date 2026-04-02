---
name: eval-harness
description: Eval-driven development framework for AI-assisted workflows. Activates when defining pass/fail criteria, measuring agent reliability, creating regression test suites, or benchmarking performance. Covers capability evals, regression evals, grader types, pass@k metrics, and ground truth management.
origin: sentinel
tools: Read, Write, Edit, Bash, Grep, Glob
---

# Eval Harness

A formal evaluation framework implementing eval-driven development (EDD) principles. Evals are the unit tests of AI development -- they define expected behavior, measure reliability, and catch regressions.

## When to Activate

- Setting up eval-driven development for AI-assisted workflows
- Defining pass/fail criteria for agent task completion
- Measuring agent reliability with pass@k metrics
- Creating regression test suites for prompt or agent changes
- Benchmarking agent performance across model versions
- Before releasing prompt changes or agent behavior changes

---

## 1. What Is Eval-Driven Development (EDD)

EDD applies TDD principles to AI systems where outputs are non-deterministic:

1. **Define** expected behavior (evals) BEFORE implementation
2. **Run** baseline evals and capture current behavior
3. **Implement** the change (prompt, tool, agent logic)
4. **Evaluate** against defined criteria
5. **Iterate** until evals pass reliably
6. **Monitor** for regressions after deployment

### Why Evals, Not Just Tests

Traditional tests verify deterministic behavior: given input X, expect output Y. AI systems produce variable outputs. Evals handle this by:
- Checking for semantic correctness rather than exact match
- Using statistical metrics (pass@k) rather than binary pass/fail
- Employing multiple grader types for different aspects of quality
- Tracking reliability over multiple runs

---

## 2. Eval Types

### Capability Evals

Test whether the system can do something it should be able to do:

```markdown
[CAPABILITY EVAL: user-registration]
Task: Register a new user with email and password
Success Criteria:
  - [ ] User record created in database
  - [ ] Password hashed (not stored in plaintext)
  - [ ] Confirmation email triggered
  - [ ] Response includes user ID and email
Expected Output: 201 Created with user object
```

Use when: adding new features, new agent capabilities, new tool integrations.

### Regression Evals

Ensure changes do not break existing functionality:

```markdown
[REGRESSION EVAL: login-flow]
Baseline: v2.3.0
Tests:
  - valid-credentials-login:       PASS/FAIL
  - invalid-password-rejection:    PASS/FAIL
  - expired-session-redirect:      PASS/FAIL
  - rate-limit-enforcement:        PASS/FAIL
Result: X/Y passed (previously Y/Y)
```

Use when: modifying prompts, changing agent logic, updating tool behavior, before releases.

---

## 3. Grader Types

### Exact Match Grader

Deterministic comparison of expected vs actual output.

```python
def grade_exact(expected: str, actual: str) -> bool:
    return expected.strip() == actual.strip()
```

Best for: structured outputs, API responses, computed values.

### Semantic Grader

Checks if the output conveys the same meaning, regardless of wording.

```python
def grade_semantic(expected: str, actual: str, threshold: float = 0.85) -> bool:
    similarity = compute_similarity(expected, actual)
    return similarity >= threshold
```

Best for: natural language outputs, explanations, summaries.

### Rubric-Based Grader

Evaluates against a multi-criteria rubric with scores.

```markdown
Rubric for: Agent Response Quality
| Criterion      | Weight | Score (1-5) |
|----------------|--------|-------------|
| Correctness    | 30%    |             |
| Completeness   | 25%    |             |
| Actionability  | 20%    |             |
| Presentation   | 15%    |             |
| Tool Usage     | 10%    |             |

Passing threshold: weighted average >= 3.5
```

Best for: complex outputs with multiple quality dimensions.

### Model-Based Grader

Uses an LLM to evaluate the output:

```markdown
[MODEL GRADER PROMPT]
You are evaluating an AI agent's response. Check:
1. Does it answer the stated question?
2. Are the facts accurate?
3. Are edge cases addressed?
4. Is the output well-structured?

Score: 1-5 (1=poor, 5=excellent)
Reasoning: [explanation]
Pass threshold: >= 4
```

Best for: open-ended outputs where programmatic grading is insufficient.

### Code-Based Grader

Deterministic checks using code execution:

```bash
# Check if file contains expected pattern
grep -q "export function handleAuth" src/auth.ts && echo "PASS" || echo "FAIL"

# Check if tests pass
pytest tests/test_auth.py -x && echo "PASS" || echo "FAIL"

# Check if build succeeds
npm run build && echo "PASS" || echo "FAIL"
```

Best for: structural requirements, build verification, test execution.

---

## 4. pass@k Metrics

### pass@k: "At Least One Success in k Attempts"

- **pass@1:** first-attempt success rate (strictest practical metric)
- **pass@3:** success within 3 attempts (typical development target)
- **pass@5:** success within 5 attempts (lenient, for complex tasks)

### pass^k: "All k Trials Succeed"

- **pass^3:** 3 consecutive successes (stability metric)
- Higher bar than pass@k -- proves consistency, not just capability

### Recommended Thresholds

| Eval Category | Metric | Target |
|---------------|--------|--------|
| Capability evals | pass@3 | >= 90% |
| Regression evals | pass^3 | 100% for release-critical paths |
| Non-critical paths | pass@1 | >= 70% |

### Interpreting Results

- **pass@1 = 100%:** reliable and deterministic
- **pass@1 = 70%, pass@3 = 95%:** works but flaky; investigate variance
- **pass@1 < 50%:** fundamentally broken; redesign the approach
- **pass@3 < 80%:** not ready for production use

---

## 5. Ground Truth Fixture Management

### What Is Ground Truth

A ground truth fixture is a verified-correct reference output for a given input. It is the "expected answer" that eval runs are compared against.

### Fixture Lifecycle

```
Define input → Generate candidate → Verify (grader) → Accept as ground truth → Use in regression evals → Regenerate when behavior intentionally changes
```

### Storage

```
evals/
  fixtures/
    feature-a/
      input.json          # The eval input
      ground-truth.json   # Verified correct output
      metadata.json       # Generation date, model version, verifier
    feature-b/
      ...
  scenarios/
    feature-a.md          # Eval definition with success criteria
    feature-b.md          # ...
  reports/
    2026-04-02.md         # Daily eval report
```

### Staleness

Ground truth fixtures become stale when:
- The underlying behavior intentionally changes (prompt update, new tool)
- The data model changes (new fields, removed fields)
- External APIs change their response format

When a fixture is stale, **regenerate it** -- do not adjust the grader to accept the drift.

### Regeneration Protocol

1. Run the eval scenario in generation mode
2. Verify the new output against success criteria (automated or manual)
3. Accept the new output as ground truth
4. Run regression evals to ensure nothing else broke
5. Update the fixture metadata with generation date and model version

---

## 6. When to Use Evals

| Trigger | Eval Type | Scope |
|---------|-----------|-------|
| Changed agent prompt | Capability + Regression | All scenarios for that agent |
| Changed tool behavior | Capability | Scenarios using that tool |
| Changed output format | Regression | All scenarios that check format |
| Pre-release | Full regression | All scenarios |
| New capability added | Capability | New scenarios + existing regression |
| Model version upgrade | Full regression | All scenarios |

---

## 7. Eval Workflow

### Phase 1: Define (Before Coding)

```markdown
## EVAL DEFINITION: feature-xyz

### Capability Evals
1. Can create new resource
2. Can validate input constraints
3. Can handle concurrent access

### Regression Evals
1. Existing CRUD operations unchanged
2. Auth flow intact
3. Error responses unchanged

### Success Metrics
- pass@3 > 90% for capability evals
- pass^3 = 100% for regression evals
```

### Phase 2: Implement

Write the code, prompt, or agent logic.

### Phase 3: Evaluate

Run each eval and record results.

### Phase 4: Report

```markdown
EVAL REPORT: feature-xyz
========================

Capability Evals:
  create-resource:     PASS (pass@1)
  validate-input:      PASS (pass@2)
  concurrent-access:   FAIL (pass@3: 1/3)
  Overall:             2/3 passed

Regression Evals:
  crud-operations:     PASS
  auth-flow:           PASS
  error-responses:     PASS
  Overall:             3/3 passed

Metrics:
  pass@1: 67% (2/3)
  pass@3: 67% (2/3)

Status: NEEDS WORK (concurrent-access failing)
```

---

## Eval Anti-Patterns

- **Overfitting prompts to known eval examples** -- the prompt works on eval inputs but fails on real inputs
- **Measuring only happy-path outputs** -- ignoring error handling and edge cases
- **Ignoring cost and latency drift** -- chasing pass rates while API costs or response times balloon
- **Allowing flaky graders in release gates** -- non-deterministic graders producing inconsistent results
- **Stale fixtures** -- comparing against outdated ground truth that no longer reflects desired behavior
- **Eval theater** -- running evals that always pass and provide no signal

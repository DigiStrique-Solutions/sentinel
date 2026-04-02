---
name: adversarial-eval
description: Convergence protocol for auditing work quality. Activates when evaluating test quality, auditing prompts, reviewing architecture, or when an agent's output needs adversarial verification. Enforces multi-round evaluation with convergence checks and a max-3-round limit.
origin: sentinel
---

# Adversarial Evaluation

When an agent writes tests, audits prompts, or reviews architecture, the output is often incomplete on first pass. Each new evaluation finds new issues. This skill enforces **convergence** so you do not loop forever.

## When to Activate

- Evaluating test quality written by an agent
- Auditing agent prompts or system prompts
- Reviewing architecture proposals
- Any situation where Agent A produces work and Agent B must verify it
- Quality gates that require adversarial verification

---

## 1. The Problem

Without convergence discipline, adversarial evaluation degenerates:

1. Agent A writes tests -- all pass
2. Agent B evaluates tests -- finds 5 are meaningless (can never fail)
3. Agent A fixes -- Agent B finds 3 more issues
4. Repeat forever -- never converges

The same pattern occurs with prompt audits, code reviews, and architecture reviews.

---

## 2. The Convergence Protocol

### Step 1: Initial Work (Agent A)

- Produce the work (tests, prompt, review, architecture)
- Save output with explicit claims: "I verified X, Y, Z"
- Be specific about what was checked and what was not

### Step 2: Adversarial Eval (Agent B -- DIFFERENT Session)

Agent B's ONLY job is to find flaws in Agent A's work.

Requirements:
- Produce a **numbered list of specific issues**
- Each issue must include:
  - File and line number (or section reference)
  - What is wrong
  - Why it matters
  - How to fix it
- Save as `vault/evals/YYYY-MM-DD-<slug>-round-N.md`

### Step 3: Fix (Agent A or Agent C)

- Fix ONLY the issues Agent B found
- Do NOT add new features or refactor unrelated code
- Produce a diff showing exactly what changed

### Step 4: Re-Eval (Agent B or Agent D -- Fresh Eyes)

- Evaluate ONLY the fixes from Step 3
- Check if original issues are resolved
- Check if fixes introduced NEW issues
- Save as `vault/evals/YYYY-MM-DD-<slug>-round-N+1.md`

### Step 5: Convergence Check

Compare Round N issues vs Round N+1 issues:

- **Converged:** Round N+1 found 0 new issues AND all Round N issues are resolved
- **Not converged:** Repeat Steps 3-4
- **MAX 3 ROUNDS** -- if not converged after 3 rounds, escalate to the user

### Why 3 Rounds

- Round 1 typically finds 60-70% of issues
- Round 2 finds 20-25% more
- Round 3 finds 5-10% more
- Beyond Round 3: diminishing returns; the remaining issues likely require human judgment or a fundamentally different approach

---

## 3. Test Quality Checklist (for Agent B)

For EACH test, verify all six criteria:

### DELETE TEST
If I delete the implementation being tested, does this test fail?
- If no: the test is testing a mock, not the code. Rewrite it.

### WRONG OUTPUT
If the function returns garbage, does this test catch it?
- If no: the assertions are too weak (e.g., `is not None`). Add specific assertions.

### NOT TESTING MOCKS
Is the test exercising real code or just verifying mock setup?
- If mocks: the test provides false confidence. Mock only external dependencies.

### SPECIFIC ASSERTIONS
Does it assert specific values, not just `is not None` or `is True`?
- If vague: replace with exact expected values, counts, or patterns.

### EDGE CASES
Are error cases and boundary conditions tested?
- If only happy path: add tests for empty, null, zero, negative, boundary, and error inputs.

### INDEPENDENCE
Does this test depend on other tests' state or execution order?
- If dependent: refactor to use setup/teardown or fresh fixtures per test.

---

## 4. Mutation Testing (Gold Standard)

The ultimate test quality check: mutate the implementation and verify tests fail.

### Concept

1. Automatically modify the source code (change `>` to `>=`, `+` to `-`, `True` to `False`)
2. Run the test suite against each mutation
3. If tests still pass with a mutation, they are not catching that behavior

### Tools

```bash
# Python (mutmut)
pip install mutmut
mutmut run --paths-to-mutate=src/module.py --tests-dir=tests/

# TypeScript (stryker)
npx stryker run --mutate "src/module.ts"

# Go (go-mutesting)
go install github.com/zimmski/go-mutesting/cmd/go-mutesting@latest
go-mutesting ./pkg/...
```

### Interpreting Results

| Mutation Score | Quality Assessment |
|----------------|-------------------|
| 90%+ | Excellent test quality |
| 70-90% | Good, but gaps exist |
| 50-70% | Tests are likely testing mocks, not code |
| Below 50% | Tests provide false confidence; rewrite needed |

### When to Use

- After writing a test suite for a critical module
- When adversarial eval finds that tests pass with deleted implementations
- As a final quality check before declaring test coverage complete
- Not needed for trivial getters/setters or configuration code

---

## 5. Prompt Audit Convergence

For system prompt and agent prompt reviews, use the same convergence protocol with prompt-specific criteria.

### Round 1: Baseline Audit

Evaluate the prompt for:
- **Missing instructions:** behaviors the prompt should specify but does not
- **Contradictions:** two instructions that conflict with each other
- **Gaps:** scenarios the prompt does not address
- **Ambiguity:** instructions that could be interpreted multiple ways
- **Verbosity:** unnecessary repetition that wastes context tokens

Rate each issue:
- **CRITICAL:** will cause incorrect behavior in common scenarios
- **HIGH:** will cause incorrect behavior in edge cases
- **MEDIUM:** reduces quality but does not cause failures
- **LOW:** cosmetic or stylistic

Save to `vault/evals/YYYY-MM-DD-prompt-audit-round-1.md`

### Round 2: Fix and Re-Audit

1. Fix all CRITICAL and HIGH issues
2. Have a DIFFERENT agent (or a fresh session) re-audit
3. The re-audit MUST reference Round 1's issue list
4. New issues get added; resolved issues get marked with checkmarks
5. Save to `vault/evals/YYYY-MM-DD-prompt-audit-round-2.md`

### Round 3: Final Check

Only if Round 2 found new CRITICAL or HIGH issues:
1. Focus ONLY on unresolved items
2. If no new CRITICAL or HIGH issues found, the audit has converged

---

## 6. Eval File Structure

```
vault/evals/
  2026-04-02-test-quality-round-1.md
  2026-04-02-test-quality-round-2.md
  2026-04-02-prompt-audit-round-1.md
  2026-04-02-prompt-audit-round-2.md
  _convergence-log.md          # Tracks which evals converged and when
```

### Convergence Log Format

```markdown
# Convergence Log

| Date       | Subject          | Rounds | Converged | Notes |
|------------|------------------|--------|-----------|-------|
| 2026-04-02 | auth-tests       | 2      | Yes       | Round 2 found 0 new issues |
| 2026-04-01 | agent-prompt     | 3      | No        | Escalated to user -- ambiguity in tool selection |
| 2026-03-28 | cache-module     | 2      | Yes       | |
```

---

## 7. Workflow Summary

```
1. Agent A produces work
2. Agent B adversarially evaluates (DIFFERENT session)
   → Numbered issue list with file, issue, why, fix
3. Agent A/C fixes ONLY the listed issues
4. Agent B/D re-evaluates ONLY the fixes
5. Convergence check:
   - All issues resolved AND no new issues? → CONVERGED
   - New issues found? → Repeat from step 3
   - 3 rounds reached without convergence? → ESCALATE to user
```

---

## Key Principles

1. **Different sessions for evaluation.** An agent cannot objectively evaluate its own work in the same session.
2. **Numbered lists, not prose.** Issues must be specific and actionable, not vague complaints.
3. **Fix only what was found.** Do not add features or refactor during the fix step.
4. **Diminishing returns are real.** Stop at 3 rounds. Beyond that, you need human judgment.
5. **Mutation testing is the gold standard.** When in doubt about test quality, mutate the implementation.

---
name: sentinel-eval-harness
description: Evaluation harness for testing AI agent prompts and outputs against ground truth. Activates when designing eval scenarios, running prompt evaluations, interpreting results, or iterating on agent behavior. Covers scenario design, expectation definition, ground truth generation, regression testing, and convergence loops.
origin: sentinel
---

# Eval Harness

A framework for systematically evaluating AI agent prompts and outputs. Instead of manual spot-checking, this skill defines a repeatable process for measuring agent quality against ground truth.

## When to Activate

- Designing evaluation scenarios for a new agent or prompt
- Running prompt evaluations after changing agent behavior
- Interpreting eval results to decide whether a prompt change is an improvement
- Setting up regression testing for agent outputs
- Iterating on prompts that consistently fail verification

---

## 1. Eval Scenario Design

### What Is an Eval Scenario

An eval scenario is a structured test case for an AI agent. It includes:
- **A prompt** -- the input given to the agent
- **Context** -- any additional state (platform, user role, conversation history)
- **Expectations** -- what the output must contain or satisfy
- **Ground truth** -- a verified-correct reference output for comparison

### Scenario Structure

```
Scenario:
  id: unique-identifier
  category: single-turn | multi-turn | tool-use | reasoning | creative
  prompt: "The input to the agent"
  context:
    platform: optional platform or domain context
    history: optional prior conversation turns
  expectations:
    required_elements: [list of things the output must contain]
    forbidden_elements: [list of things the output must not contain]
    quality_description: "Human-readable description of what good looks like"
    expects_tool_calls: true | false
    expected_tools: [list of tool names if applicable]
  description: "Why this scenario exists and what it tests"
```

### Scenario Categories

| Category | What It Tests | Example |
|----------|---------------|---------|
| Single-turn | Basic prompt-response quality | "Summarize this data" |
| Multi-turn | Context retention across turns | Initial prompt + follow-up |
| Tool-use | Correct tool selection and invocation | "Fetch my recent orders" |
| Reasoning | Multi-step logic and analysis | "Compare performance across channels" |
| Creative | Open-ended generation quality | "Write a strategy document" |
| Edge case | Boundary and failure handling | Empty data, invalid inputs |

### Writing Good Scenarios

1. **One behavior per scenario.** Do not combine "does it pick the right tool" and "is the output formatted correctly" in one scenario.
2. **Specific expectations.** "The output should be good" is not testable. "The output must contain a numeric spend value and a trend direction" is.
3. **Include negative cases.** Test what the agent should NOT do (hallucinate data, call wrong tools, ignore instructions).
4. **Cover the distribution.** If agents handle 5 categories of queries, have scenarios for all 5 -- not 10 scenarios for the most common category.

---

## 2. Expectation Definition

### Types of Expectations

#### Structural Expectations
- Output contains specific fields or sections
- Output is in a required format (JSON, markdown table, bullet list)
- Output length is within acceptable range

#### Content Expectations
- Specific keywords or values are present
- Numerical values are within expected ranges
- References or citations are included where required
- Tool calls match the expected tool list

#### Quality Expectations
- Response is factually accurate (verified against ground truth)
- Response is complete (all requested information is present)
- Response is actionable (includes specific recommendations, not vague advice)
- Response does not hallucinate (only uses data that was actually available)

#### Behavioral Expectations
- Agent called the correct tools in the correct order
- Agent did not call unnecessary tools
- Agent handled errors gracefully (when error conditions are injected)
- Agent respected constraints (rate limits, data boundaries, permissions)

### Defining Expectations Precisely

```
VAGUE (bad):
  - "Response should be helpful"
  - "Agent should handle errors"
  - "Output should be formatted well"

PRECISE (good):
  - "Response must contain at least 3 item names from the mock data"
  - "When the API returns a 401 error, the agent must suggest re-authenticating"
  - "Output must be a markdown table with columns: Name, Status, Value"
```

---

## 3. Ground Truth Generation

### What Is Ground Truth

Ground truth is a verified-correct reference output for a given scenario. It represents what a correct agent response looks like.

### Generation Process

1. **Run the agent** against the scenario prompt with full context
2. **Capture the output** including any tool calls, intermediate steps, and final response
3. **Verify the output** -- manually or via an automated verifier (LLM-as-judge)
4. **Save as fixture** -- the verified output becomes the reference for future comparisons

### Verification Criteria

A verification pass should check:

| Criterion | What It Checks |
|-----------|----------------|
| Correctness | Does the response accurately answer the prompt? |
| Tool usage | Were appropriate tools called with correct parameters? |
| Completeness | Is all necessary information included? |
| Actionability | Are recommendations specific and implementable? |
| Data boundary | Does the response only use available data (no hallucination)? |
| Presentation | Is the output well-formatted and readable? |

### Fixture Management

- Store fixtures alongside scenario definitions
- Include metadata: generation timestamp, agent version, verification status
- Mark fixtures as stale after N days (configurable) -- prompt for regeneration
- Never edit fixtures manually -- always regenerate from the agent and re-verify

---

## 4. Running Evaluations

### Evaluation Modes

| Mode | What It Does | When to Use |
|------|-------------|-------------|
| Generate | Run agent, verify output, save as ground truth | After changing prompts or tools |
| Regression | Run agent, compare to existing ground truth | Before releases, after refactors |
| Full | Generate new ground truth, then run regression | Comprehensive validation |

### Execution Flow

```
1. Load scenario definition
2. Set up context (mock data, platform state, conversation history)
3. Run the agent with the scenario prompt
4. Capture: final output, tool calls, intermediate reasoning, timing
5. Verify against expectations (structural, content, quality, behavioral)
6. Compare to ground truth (if regression mode)
7. Report: pass/fail per criterion, overall verdict, timing SLAs
```

### Batch Running

For running multiple scenarios:
- Run scenarios in the same category together
- Skip scenarios that already have fresh fixtures (configurable)
- Report aggregate pass rates by category
- Flag any scenario that was passing and is now failing (regression)

### SLA Thresholds

Define timing SLAs for agent performance:

| Metric | What It Measures |
|--------|-----------------|
| Time to first token | How quickly the agent starts responding |
| Total duration | End-to-end time for complete response |
| Tool call duration | Time spent in tool execution |
| Plan completion time | Time to complete multi-step plans |

Set thresholds based on your application's requirements. A response that is correct but takes 5 minutes may still be a failure.

---

## 5. Interpreting Results

### Pass/Fail Analysis

For each failed scenario, determine:

1. **Which criterion failed?** (correctness, completeness, tool usage, etc.)
2. **Is it a prompt issue or a tool issue?** Wrong tool called = routing problem. Wrong output from right tool = prompt problem.
3. **Is it a regression?** Was this scenario passing before the change?
4. **Is the ground truth stale?** If the expected behavior has intentionally changed, regenerate ground truth first.

### Common Failure Patterns

| Pattern | Likely Cause | Fix |
|---------|-------------|-----|
| Wrong tools called | Routing or skill loading mismatch | Check tool registration, skill files |
| Correct tools, wrong output | Prompt instructions unclear | Clarify prompt, add examples |
| Hallucinated data | Agent generating data instead of using tools | Add explicit instruction: "only use data from tool results" |
| Incomplete response | Prompt too vague about requirements | Add specific output requirements |
| Format wrong | Missing format instructions | Add output format specification with examples |
| SLA violation | Slow tools or too many tool calls | Optimize tool implementation, reduce unnecessary calls |

### Aggregate Metrics

Track over time:
- **Pass rate by category** -- which types of scenarios are weakest?
- **Regression rate** -- how often do passing scenarios start failing?
- **Mean verification score** -- average quality across all scenarios
- **SLA compliance** -- percentage of scenarios within timing thresholds

---

## 6. Iterative Prompt Improvement

### The Eval-Fix Loop

```
1. Run eval suite
2. Identify failing scenarios
3. Diagnose root cause (prompt, tool, routing, data)
4. Make targeted fix
5. Re-run ONLY the failing scenarios
6. If they pass, run the FULL suite (catch regressions)
7. If full suite passes, commit
8. If new failures appear, repeat from step 2
```

### Automated Iteration

For prompts that need many refinement cycles, use an automated loop:

```
Loop until convergence or max iterations:
  1. Run eval scenario
  2. If pass: done
  3. If fail: read rejection reasoning
  4. Adjust prompt based on reasoning
  5. Re-run
```

Set a maximum iteration count (10 is a reasonable default). If the prompt does not converge after max iterations, the problem may be architectural, not prompt-level.

### Convergence Criteria

A prompt change is converged when:
- All previously-passing scenarios still pass
- The target failing scenario now passes
- No new failures were introduced

---

## 7. Scenario Maintenance

### Adding New Scenarios

When adding a new capability to the agent:
1. Write the scenario BEFORE changing the prompt or tools
2. Run it -- it should fail (the capability does not exist yet)
3. Implement the capability
4. Run it -- it should pass
5. Generate and verify ground truth

This is TDD applied to AI agent behavior.

### Retiring Scenarios

Remove scenarios when:
- The capability they test has been intentionally removed
- The scenario is a duplicate of another
- The scenario tests implementation details that have been refactored

Never retire a scenario because it is failing. Fix the agent or update expectations.

### Coverage Gaps

Periodically audit scenario coverage:
- Are all agent capabilities tested?
- Are all tool categories represented?
- Are error conditions tested?
- Are multi-turn interactions tested?
- Are edge cases (empty data, large inputs, ambiguous queries) tested?

---

## Key Principles

1. **Eval before ship.** Never deploy prompt or tool changes without running the eval suite.
2. **Precise expectations beat vague quality checks.** "Output must contain X" is testable. "Output should be good" is not.
3. **Ground truth has a shelf life.** Regenerate fixtures when agent behavior intentionally changes.
4. **Fix the agent, not the eval.** If a scenario fails, the default assumption is that the agent is wrong. Only update expectations when behavior has intentionally changed.
5. **Aggregate metrics reveal trends.** Individual scenario failures are symptoms. Pass rates by category reveal systemic issues.

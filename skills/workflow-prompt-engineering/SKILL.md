---
name: sentinel-workflow-prompt-engineering
description: Disciplined prompt-engineering workflow — define, research, write, test, iterate, document. Use whenever the user says "write a prompt", "system prompt", "agent prompt", "tune the prompt", "prompt isn't working", "LLM keeps doing X", "improve the agent", "eval the prompt", or otherwise asks to create or improve an LLM/agent prompt — even if they don't explicitly say "workflow". Enforces systematic evaluation over manual testing, requires anti-examples, and changes prompts one variable at a time so regressions are traceable. Six steps — define, research, write, test, iterate, document.
workflow: true
workflow-steps: 6
allowed-tools: Read Grep Glob Bash Edit Write MultiEdit TodoWrite
origin: sentinel
---

# Prompt Engineering Workflow

Creating, testing, and iterating on LLM prompts and agent system prompts.

This is a Sentinel workflow skill. When it activates, the `sentinel-workflow-runner` protocol drives execution — creates a run directory, checkpoints progress after each step, and supports resumption across sessions. You do not need to invoke the runner explicitly; it activates alongside this skill.

## Protocol summary

At the top of the workflow, create a new run:

```bash
RUN_ID=$(bash "${CLAUDE_PLUGIN_ROOT}/scripts/workflow-state.sh" start prompt-engineering)
```

Before each numbered step, call `step-start`. After each step completes, call `step-complete` (with an artifact path if you produced one). After the final step, call `finish <run-id> completed`. On failure, call `step-fail` and follow the failure-handling rules in each section below.

Full protocol details: see `sentinel-workflow-runner` skill.

---

## 1. Define the Prompt's Job

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/workflow-state.sh" step-start "$RUN_ID" 1 "Define the Prompt's Job"
```

- [ ] What should the prompt make the agent do? (specific behavior, not vague goal)
- [ ] What inputs will it receive? (user query, context, conversation history)
- [ ] What output format is expected? (text, tool calls, structured data)
- [ ] What should it NOT do? (anti-examples are as important as examples)

**Write an artifact**: `vault/workflows/runs/$RUN_ID/artifacts/step-1-job.md` with the precise behavior, inputs, outputs, and anti-goals.

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/workflow-state.sh" step-complete "$RUN_ID" 1 "artifacts/step-1-job.md"
```

## 2. Research Before Writing

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/workflow-state.sh" step-start "$RUN_ID" 2 "Research Before Writing"
```

- [ ] Check existing prompts in the same area -- can you modify rather than create?
- [ ] Check competitor approaches if relevant
- [ ] Read the relevant architecture docs to understand the agent's capabilities

**Write an artifact**: `artifacts/step-2-research.md` listing existing prompts inspected and any reusable patterns.

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/workflow-state.sh" step-complete "$RUN_ID" 2 "artifacts/step-2-research.md"
```

## 3. Write the Prompt

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/workflow-state.sh" step-start "$RUN_ID" 3 "Write the Prompt"
```

### Structure:
- Clear role definition
- Explicit constraints (what NOT to do)
- Output format specification
- Examples of good and bad responses
- Tool usage instructions (which tools to call, when, in what order)

### Best practices:
- Be specific -- "Respond in 2-3 sentences" not "Be concise"
- Include anti-examples -- "Do NOT hallucinate data" not just "Be accurate"
- Use structured output formats when possible (JSON, markdown tables)
- Test with edge cases (empty input, very long input, adversarial input)

**Write an artifact**: `artifacts/step-3-prompt.md` with the prompt file path and a summary of the structure decisions.

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/workflow-state.sh" step-complete "$RUN_ID" 3 "artifacts/step-3-prompt.md"
```

## 4. Test

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/workflow-state.sh" step-start "$RUN_ID" 4 "Test"
```

### Quick validation:
- Test with 5-10 representative inputs
- Include at least 2 edge cases
- Include at least 1 adversarial input

### Systematic evaluation:
- Define evaluation criteria (correctness, completeness, format compliance)
- Create a test suite of 20+ prompts with expected outputs
- Score each response against criteria
- Track pass rate across iterations

### Regression testing:
- After changing a prompt, re-run the full test suite
- Ensure improvements on target cases don't regress other cases

**Write an artifact**: `artifacts/step-4-test.md` with the eval suite file path, the criteria, and the current pass rate.

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/workflow-state.sh" step-complete "$RUN_ID" 4 "artifacts/step-4-test.md"
```

## 5. Iterate

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/workflow-state.sh" step-start "$RUN_ID" 5 "Iterate"
```

If the prompt doesn't produce the desired output:

- [ ] Identify which evaluation criteria failed
- [ ] Adjust prompt wording and re-test
- [ ] Common fixes:
  - Add more specific constraints
  - Add examples of the desired output
  - Add anti-examples of common failures
  - Restructure the prompt (role -> context -> task -> format)
  - Break complex prompts into smaller, focused ones

**Write an artifact**: `artifacts/step-5-iterate.md` recording each tweak, the reason, and the resulting pass-rate change.

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/workflow-state.sh" step-complete "$RUN_ID" 5 "artifacts/step-5-iterate.md"
```

## 6. Document

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/workflow-state.sh" step-start "$RUN_ID" 6 "Document"
```

- [ ] If the prompt required non-obvious tuning, document why in `vault/gotchas/`
- [ ] If the prompt change affects agent behavior, update `vault/changelog/`
- [ ] Version your changes -- track what changed and why

**Write an artifact**: `artifacts/step-6-document.md` listing vault entries touched and the version-control note.

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/workflow-state.sh" step-complete "$RUN_ID" 6 "artifacts/step-6-document.md"
bash "${CLAUDE_PLUGIN_ROOT}/scripts/workflow-state.sh" finish "$RUN_ID" completed
```

## Key Rules

- **Test systematically, not manually.** Manual testing doesn't catch regressions.
- **Anti-examples matter.** Tell the agent what NOT to do -- this prevents the most common failures.
- **Prompt changes affect all users.** Test with multiple scenarios, not just the one you're fixing.
- **Iterate in small steps.** Change one thing at a time so you know what improved (or broke) the output.

#workflow #prompts #engineering

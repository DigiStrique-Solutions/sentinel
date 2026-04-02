# Prompt Engineering Workflow

Creating, testing, and iterating on LLM prompts and agent system prompts.

## 1. Define the Prompt's Job

- [ ] What should the prompt make the agent do? (specific behavior, not vague goal)
- [ ] What inputs will it receive? (user query, context, conversation history)
- [ ] What output format is expected? (text, tool calls, structured data)
- [ ] What should it NOT do? (anti-examples are as important as examples)

## 2. Research Before Writing

- [ ] Check existing prompts in the same area -- can you modify rather than create?
- [ ] Check competitor approaches if relevant
- [ ] Read the relevant architecture docs to understand the agent's capabilities

## 3. Write the Prompt

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

## 4. Test

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

## 5. Iterate

If the prompt doesn't produce the desired output:

- [ ] Identify which evaluation criteria failed
- [ ] Adjust prompt wording and re-test
- [ ] Common fixes:
  - Add more specific constraints
  - Add examples of the desired output
  - Add anti-examples of common failures
  - Restructure the prompt (role -> context -> task -> format)
  - Break complex prompts into smaller, focused ones

## 6. Document

- [ ] If the prompt required non-obvious tuning, document why in `vault/gotchas/`
- [ ] If the prompt change affects agent behavior, update `vault/changelog/`
- [ ] Version your changes -- track what changed and why

## Key Rules

- **Test systematically, not manually.** Manual testing doesn't catch regressions.
- **Anti-examples matter.** Tell the agent what NOT to do -- this prevents the most common failures.
- **Prompt changes affect all users.** Test with multiple scenarios, not just the one you're fixing.
- **Iterate in small steps.** Change one thing at a time so you know what improved (or broke) the output.

#workflow #prompts #engineering

# Prompt Engineering Workflow

Creating, testing, and iterating on LLM prompts and agent system prompts.

## 1. Define the Prompt's Job

- [ ] What should the prompt make the LLM do? (specific behavior, not vague goal)
- [ ] What inputs will it receive? (user query, context, structured data)
- [ ] What output format is expected? (text, tool calls, structured data, code)
- [ ] What should it NOT do? (anti-examples are as important as examples)

## 2. Research Before Writing

- [ ] Check existing prompts in the same area -- can you modify rather than create?
- [ ] Check competitor approaches or published prompt engineering guides
- [ ] Understand the LLM's capabilities and limitations for this task

## 3. Write the Prompt

Key elements:
- [ ] Clear role definition
- [ ] Explicit constraints (what NOT to do)
- [ ] Output format specification
- [ ] Examples of good and bad responses
- [ ] Edge case handling instructions

## 4. Test

- [ ] Test with representative inputs (not just the happy path)
- [ ] Test with adversarial inputs (attempts to break or bypass instructions)
- [ ] Test with edge cases (empty input, very long input, ambiguous input)
- [ ] If an eval pipeline exists, add the prompt as a test scenario
- [ ] Record pass/fail results for each test case

## 5. Iterate

If the prompt doesn't produce the desired output:
- [ ] Identify which specific outputs were wrong
- [ ] Adjust prompt wording and re-test
- [ ] Add explicit examples for the failure cases
- [ ] Consider few-shot examples if zero-shot isn't working

## 6. Document

- [ ] If the prompt required non-obvious tuning, document why in `vault/gotchas/`
- [ ] If the prompt establishes a new pattern, add to `vault/decisions/`
- [ ] Version your changes -- prompt diffs are as important as code diffs

## Key Rules

- **Test systematically, not manually.** Manual testing doesn't catch regressions.
- **Anti-examples matter.** Tell the LLM what NOT to do -- this prevents the most common failures.
- **Prompt changes affect all users.** Test with multiple scenarios, not just the one you're fixing.

#workflow #prompts #engineering

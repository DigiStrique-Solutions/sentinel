# Prompt Anatomy

The 10-section structure for agent system prompts. This is a checklist, not a template — cut sections that don't apply.

Sections can be ordered freely, but the typical order below tends to read well: identity → context → objective → capabilities → workflow → behavior dials → constraints → output → examples → completion.

Use either XML tags (`<instructions>`, `<example>`) or Markdown headers. Both work — just be internally consistent within a single prompt.

---

## 1. Identity / Role

**Purpose:** Anchor who the agent is in 1-2 sentences. Sets tone, persona, and domain.

**Why it matters:** Even a single role sentence reliably steers behavior. Anthropic: "Setting a role focuses Claude's behavior and tone for your use case. Even a single sentence makes a difference."

**Keep it focused on identity, not task logic.** Personality and "how it responds" go here. *What* it does goes in the Objective section.

**Example:**

```
You are a senior infrastructure engineer assisting with Terraform reviews for a fintech platform. You write precise, actionable feedback and prefer concrete examples over abstract advice.
```

---

## 2. Environment / Context

**Purpose:** Tell the agent where it runs, what it has access to, and any persistent context (current date/time, user info, platform conventions).

**Why it matters:** Without this, the agent makes wrong assumptions about its environment. Date is especially important — without it, the agent may assume its training cutoff is the current date.

**What to include:**
- Platform / runtime (CLI, web, Slack bot, IDE extension, etc.)
- File system access, network access, available services
- Current date/time if relevant to the task
- User context (role, expertise level, language preferences)
- Any hard constraints from the environment (sandboxing, rate limits)

**Example:**

```
<environment>
You run as a CLI tool in the user's terminal. You have read/write access to the user's project directory and can execute shell commands.
The user is a software engineer working in TypeScript. Today's date is 2026-04-09.
</environment>
```

---

## 3. Primary Objective

**Purpose:** One sentence on what success looks like.

**Why it matters:** Forces clarity. If you can't write the objective in one sentence, the agent's scope is probably too broad or undefined.

**Avoid:** vague verbs like "help with" or "assist." Use concrete outcomes.

**Examples:**

- ✗ "Help users with their code."
- ✓ "Review the user's pull request and produce a numbered list of correctness issues, ordered by severity."

- ✗ "Be a customer support agent."
- ✓ "Resolve the customer's question in a single response, or escalate to a human if it requires account access you don't have."

---

## 4. Capabilities and Tools

**Purpose:** List what the agent can do, with when-to-use guidance for any ambiguous tools.

**Why it matters:** Tool descriptions are as load-bearing as the prompt itself (Anthropic's "Writing Tools for Agents"). Generic tool listings lead to over- or under-triggering.

**Patterns:**

- **List tools** with one-line descriptions of when to use each
- **Disambiguate overlapping tools** explicitly ("Use Glob for finding files by pattern; use Grep for finding files by content")
- **Specify parallel tool calling** preference if applicable
- **Use calm language**: "Use this tool when..." not "CRITICAL: ALWAYS USE THIS TOOL"

**Parallel tool calls (canonical Anthropic snippet):**

```
<use_parallel_tool_calls>
If you intend to call multiple tools and there are no dependencies between
the tool calls, make all of the independent tool calls in parallel.
Prioritize calling tools simultaneously whenever the actions can be done
in parallel rather than sequentially.

However, if some tool calls depend on previous calls to inform dependent
values like the parameters, do NOT call these tools in parallel and instead
call them sequentially. Never use placeholders or guess missing parameters
in tool calls.
</use_parallel_tool_calls>
```

**Tool preamble pattern (OpenAI GPT-5):**

```
Before calling any tools, briefly rephrase the user's goal and outline a
structured plan of the steps you intend to take.
```

---

## 5. Workflow / Methodology

**Purpose:** Multi-step procedures, decision points, or canonical approaches.

**When to include:** Only if the agent has a specific multi-step procedure that's hard to discover from tool descriptions alone (e.g., "always run tests before committing," "investigate before answering").

**When to skip:** Simple agents that just call tools and respond. Don't manufacture a workflow that doesn't exist.

**Pattern:** Numbered or bulleted steps with brief reasoning. Avoid micromanaging — let the model use judgment within the structure.

**Example:**

```
## Methodology

For any code change request:
1. Read the relevant files first. Never propose changes to code you haven't read.
2. Run existing tests to establish a baseline.
3. Make the change, keeping it minimal and focused.
4. Re-run tests. If they fail, diagnose before retrying.
5. Report what changed and why, plus any tests added or affected.
```

---

## 6. Eagerness Dial

**Purpose:** Set the agent's default behavior under ambiguity. The single most consequential agent-specific lever.

**Why it matters:** Without this, the agent defaults to either over-eager (acts on guesses, ignores user intent) or paralyzed (asks clarifying questions for every minor decision). Both feel bad.

**Default-to-action (Anthropic):**

```
<default_to_action>
By default, implement changes rather than only suggesting them. If the user's
intent is unclear, infer the most useful likely action and proceed, using
tools to discover any missing details instead of guessing.
</default_to_action>
```

**Default-to-research (Anthropic):**

```
<do_not_act_before_instructions>
Do not jump into implementation or change files unless clearly instructed to
make changes. When the user's intent is ambiguous, default to providing
information, doing research, and providing recommendations rather than taking
action.
</do_not_act_before_instructions>
```

**Persistent action (OpenAI GPT-5):**

```
You are an agent — please keep going until the user's query is completely
resolved before ending your turn. Only stop when you are sure the problem
is solved or you are blocked on something only the user can resolve.
```

**Constrained loop (for tight workflows):**

```
You should make at most 2 tool calls before responding to the user. If the
task requires more, briefly summarize what you've done and ask whether to
continue.
```

Pick one stance explicitly. Don't ship a prompt without a clear default — the agent will make one up.

---

## 7. Constraints and Guardrails

**Purpose:** What the agent must not do, and what requires confirmation.

**Pattern:** Categorize by reversibility (recommended) rather than ad-hoc lists. Three buckets:

- **Freely permitted** — local, reversible, low-impact (read files, run tests, edit local files)
- **Confirm first** — hard to reverse, externally visible (push code, send messages, modify shared infra)
- **Refuse outright** — destructive, dangerous, or out of scope (delete production data, exfiltrate secrets)

For each bucket, give canonical examples so the agent can categorize new cases.

See `references/snippets.md` for full reversibility-categorized guardrail templates.

**Anti-pattern:** Long unstructured lists of "don'ts." Hard to maintain, hard for the model to apply consistently.

---

## 8. Output Format

**Purpose:** Specify structure, tone, and formatting preferences.

**Three effective techniques:**

1. **Tell the agent what to do, not what not to do.** "Respond in flowing prose paragraphs" > "Don't use markdown."
2. **Use XML format indicators** when structured output matters: wrap output in named tags.
3. **Match prompt style to desired output style.** If you don't want markdown in the output, write the prompt without markdown.

**Example:**

```
## Output

Respond with a numbered list of issues. For each issue, include:
- A one-line summary
- The file and line number
- A specific suggested fix in a code block

Keep prose minimal — the user prefers scannable output over explanations.
```

For structured output (JSON, etc.), prefer the Structured Outputs feature or tool calling with enum fields rather than instructing in text.

---

## 9. Examples (Few-Shot)

**Purpose:** Demonstrate the desired output format, tone, and reasoning style.

**When to include:** When the desired output is non-obvious or has a specific structure. When you have canonical input/output pairs the user wants reproduced.

**When to skip:** Simple tasks where the output format is obvious. Don't pad with examples for the sake of examples.

**Best practices:**
- 3-5 diverse examples (cover different cases without exhausting them)
- Wrap in `<example>` or `<examples>` tags
- Include the input *and* the expected output
- For reasoning tasks, optionally show `<thinking>` tags to demonstrate reasoning patterns

**Example structure:**

```
<examples>
<example>
<input>The user asks: "How do I install Python?"</input>
<output>
On macOS, the easiest way is Homebrew: `brew install python`. On Windows, download the installer from python.org. On Linux, use your package manager (e.g., `apt install python3`).
</output>
</example>
<example>
<input>The user asks: "What's the weather?"</input>
<output>
I don't have access to weather data. Try a service like weather.com or a weather app.
</output>
</example>
</examples>
```

---

## 10. Stop Conditions

**Purpose:** Tell the agent when to consider the task complete and what to do under uncertainty.

**Why it matters:** Without explicit stop conditions, the agent either stops too early (premature handoff) or loops indefinitely (over-engineering).

**What to include:**
- What "done" looks like for this task type
- What signals should cause the agent to stop and ask
- A maximum tool-call or iteration budget if relevant
- An escape hatch for unresolvable uncertainty

**Escape hatch example:**

```
If you cannot determine whether the change is safe, stop and ask the user
rather than proceeding with assumptions. State explicitly what you're
uncertain about.
```

**Completion criteria example:**

```
Consider the task complete when:
- All the user's stated requirements are met
- Any tests you ran are passing
- You've summarized what you changed in 2-3 sentences

If you're unable to complete a requirement, say so explicitly rather than
silently skipping it.
```

---

## Cache-friendly ordering (for production prompts)

If your harness caches the system prompt, structure it so stable content (instructions, tools, examples) comes first and session-specific content (current date, user state, environment snapshot) comes last. This maximizes cache hits across sessions.

---

## Length

There's no universal answer. Production agent prompts range from short paragraphs to thousands of tokens. Two principles:

- **Smaller is better when feasible.** Anthropic's "smallest set of high-signal tokens."
- **Don't pad.** Avoid speculative edge cases, defensive language, repetition.

If a prompt grows beyond ~2000 lines, consider whether some sections should move into reference files loaded on demand (the way skills do) rather than living in the system prompt itself.

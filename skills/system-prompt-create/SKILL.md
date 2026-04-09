---
name: sentinel-system-prompt-create
description: Create high-quality system prompts for AI agents through a guided interview, structured drafting, and self-review. Use when users want to write a system prompt for an agent, design a new agent's instructions, improve an existing agent prompt, or stress-test an agent prompt for issues. Make sure to use this skill whenever the user mentions writing instructions for an agent, building an agent, drafting an agent prompt, or any phrase like "make a prompt for an agent that..." or "I'm building an agent that needs to..." even if they don't say "system prompt" explicitly.
origin: sentinel
---

# System Prompt Create

A skill for authoring production-quality system prompts for AI agents.

System prompts have a small number of high-leverage components that can't be guessed and a large number of common pitfalls that quietly degrade quality. This skill exists to:

1. **Interview** the user to extract the irreducible minimum of context (the parts that *can't* be inferred)
2. **Draft** a structured prompt that follows current best practices
3. **Self-review** for the common pitfalls that 2025-2026 model behavior has surfaced
4. **Optionally grill or eval** the prompt for users who want more rigor

Be flexible. Some users want a tight, surgical prompt for a production agent — others are sketching ideas and want to vibe. Read the room.

## Core Principles

Internalize these before drafting anything. They come from the most current best practices (Anthropic's context-engineering docs, Claude 4.6 best practices, OpenAI's GPT-5 prompting guide, and analysis of leaked production prompts):

- **Right altitude.** The goal is "the smallest set of high-signal tokens that maximize the desired outcome." Specific enough to guide, flexible enough to generalize. Avoid both edge-case stuffing and vague platitudes.
- **Calm beats aggressive.** Modern models (Claude 4.6, GPT-5) overtrigger on "CRITICAL: YOU MUST" patterns. Use declarative, normal language. "Use this tool when..." beats "CRITICAL: ALWAYS USE THIS TOOL."
- **Explain the why.** A reason lets the model generalize to unanticipated cases. "Never use ellipses because the response will be read by a TTS engine that can't pronounce them" beats "NEVER use ellipses."
- **Positive framing.** "Respond in flowing prose paragraphs" beats "Don't use markdown."
- **No contradictions.** GPT-5 burns reasoning tokens trying to reconcile contradictory instructions. Review the whole prompt for consistency before shipping.
- **Trust the model.** Don't add defensive padding for cases that can't happen. The right amount of complexity is what the task actually requires.
- **The eagerness dial is the most consequential agent-specific lever.** Get it wrong and the agent feels either pushy or paralyzed.

---

## The Workflow

### Phase 1: Capture Intent (the interview)

Start by extracting context from the conversation if any exists. The user may have already described what they want — pull from there first, then ask only the gaps.

Then run the **Tier 1 questions** below — the irreducible minimum. These map directly to the most consequential levers in agent prompts. **Skip any question the user has already answered.** Ask a few at a time, not all at once. For each question, a one-sentence explanation of *why* you're asking can teach the user as you go — don't lecture, just briefly contextualize.

#### Tier 1 — Always cover these (in some form)

1. **Primary objective** — "In one sentence, what is the single most important thing this agent should accomplish?"
2. **Tools and capabilities** — "What tools or capabilities does the agent have? (e.g., specific MCPs, file access, web search, custom functions.) If you haven't decided yet, what kinds of actions should it be able to take?"
3. **Environment and user** — "Where will this agent run, and who's the user? (e.g., a CLI tool for developers, a customer support chat for non-technical users, a Slack bot for an internal team.)"
4. **Eagerness dial** — "When the user's intent is ambiguous, should the agent (a) take its best guess and act, or (b) stop and ask / do research first?" Briefly note: this is the single biggest behavioral lever for agents.
5. **Guardrails** — "What should this agent never do? Especially: any destructive, irreversible, or externally-visible actions you want it to confirm before taking, or refuse outright."
6. **Done condition** — "How does the agent know it's finished? What should it do if it gets stuck?"

#### Tier 2 — Ask only if relevant

Based on the Tier 1 answers, follow up only on whichever of these are load-bearing:

- **Output format and tone** — only if structured output, specific voice, or brand consistency matters
- **Workflow / methodology** — only if there's a specific multi-step procedure the agent must follow
- **Few-shot examples** — "Do you have any input/output pairs or canonical examples worth baking in?"
- **Sub-agent orchestration** — only if the agent will spawn or coordinate sub-agents
- **Memory / state handling** — only if the agent runs across sessions or compacts context
- **Reasoning style** — only if the user has strong opinions about chain-of-thought visibility

#### Escape hatches (always offer)

- **"Skip — use sensible defaults"** for any individual question
- **"Just vibe with me, here's a rough description"** — single-shot mode, draft from one paragraph
- **"I have an existing prompt, just improve it"** — skip straight to self-review and iteration

### Phase 2: Draft the Prompt

Use the standard structure below. Read `references/prompt-anatomy.md` for full section-by-section guidance and examples.

1. **Identity / role** — 1-2 sentences anchoring who the agent is
2. **Environment / context** — where it runs, what it has access to, current date/time if relevant
3. **Primary objective** — one sentence on what success looks like
4. **Capabilities and tools** — list with when-to-use guidance for ambiguous tools
5. **Workflow / methodology** — multi-step procedures, decision points (only if needed)
6. **Eagerness dial** — explicit default-to-action or default-to-research stance
7. **Constraints and guardrails** — categorized by reversibility (see `references/snippets.md`)
8. **Output format** — positively framed
9. **Examples** — 3-5 diverse few-shot in `<example>` tags, only if they add value
10. **Stop conditions** — what "done" means + escape hatches under uncertainty

Use either XML tags (`<instructions>`, `<example>`, etc.) or Markdown headers — both work, just be internally consistent. For long reference material, put it near the top above the query.

**Don't fill out the structure mechanically.** Some sections won't apply to every agent. A simple read-only research agent doesn't need elaborate guardrails. A single-purpose tool wrapper might not need a workflow section. The structure is a checklist, not a template — use judgment, and cut anything that feels like padding.

For each section you write, ask yourself: *would a new colleague know what to do?* If not, add the missing context. If a section feels like padding, cut it.

`references/snippets.md` has battle-tested snippets from Anthropic for common patterns (anti-hallucination, parallel tool calls, eagerness dials, context compaction awareness, reversibility-based guardrails). Pull from these rather than reinventing them — they've been tested at scale.

### Phase 3: Self-Review

Before showing the user, run through this checklist. Read `references/anti-patterns.md` for the full list with BAD/GOOD examples.

- [ ] **Contradictions** — read the whole prompt; flag any sections that conflict
- [ ] **ALL-CAPS / "CRITICAL: YOU MUST"** — replace with calm declarative language unless the user specifically requested emphasis
- [ ] **Negative-only instructions** — convert "don't do X" to "do Y" wherever possible
- [ ] **Vague language** — "be helpful," "use best judgment," "as appropriate" — replace with concrete behaviors
- [ ] **Missing why** — every non-obvious instruction should have a brief reason
- [ ] **Defensive padding** — error handling for impossible cases, fallbacks for guaranteed inputs
- [ ] **Edge-case stuffing** — long lists of "what if" rules instead of high-level heuristics
- [ ] **Eagerness mismatch** — does the prompt's overall tone match the eagerness dial setting?
- [ ] **Tool description quality** — for each tool, is the "when to use" guidance clear and unambiguous?
- [ ] **Stop conditions** — is there an escape hatch for uncertainty?
- [ ] **Trust boundaries** — if the agent processes untrusted input, are document/input boundaries clearly delimited (e.g., wrapped in `<document>` tags)?

Fix issues directly, then present the prompt to the user with a brief note on what you adjusted and why.

### Phase 4: Present

Show the user the draft prompt in a code block. Briefly highlight:

- The eagerness stance you took (and why)
- Any guardrails you added beyond what they specified
- Any sections you intentionally omitted
- Anything you weren't sure about that needs their input

Then offer next steps:

- **Iterate** — "Anything you want changed?"
- **Grill mode** — "Want me to stress-test this prompt for issues? (See grill mode below.)"
- **Eval loop** — "Want to test this prompt against some real scenarios?"
- **Done** — "Ship it."

---

## Grill Mode (optional, opt-in)

For users who want rigorous adversarial review of a prompt before shipping. This is the same spirit as the `grill-me` skill but focused specifically on system prompts.

**When to suggest it:**

- The user explicitly asks for it ("grill it," "stress test," "find issues," "audit this")
- The prompt is going into production and the user wants rigor
- You're improving an existing prompt and the user wants a thorough audit
- The first draft has obvious gaps but the user isn't sure what to ask for

**How it works:** spawn the `griller` subagent with the draft prompt. It reads `agents/griller.md` and runs through:

1. **Adversarial scenarios** — "imagine a user does X. What does the prompt say? Is the answer clear? Is it the *right* answer?"
2. **Contradiction hunt** — pairwise comparison of instructions
3. **Ambiguity hunt** — anywhere the model could plausibly do two different things
4. **Missing escape hatches** — uncertainty handling, blocked-tool fallbacks
5. **Eagerness audit** — does the dial match the use case?
6. **Tool boundary check** — are tools described well enough to use correctly?

The griller returns a numbered list of issues with severity (blocker/major/minor) and suggested fixes. Apply the fixes you agree with, discuss the rest with the user.

If sub-agents aren't available, run the checklist inline yourself by reading `agents/griller.md`.

---

## Eval Loop (optional)

For prompts where you want qualitative confidence the prompt actually works on real tasks.

**When to suggest it:**

- The user is shipping the prompt to production
- The user has specific failure cases they're worried about
- The prompt has been through multiple iterations and you want to confirm progress

**How it works:**

1. **Generate test scenarios** — 3-10 realistic prompts the agent will receive in the wild. Draw from the user's real failure cases if any exist.
2. **Run** — spawn an agent with the system prompt against each scenario; capture the transcript
3. **Review** — have the user look at the outputs and flag issues
4. **Iterate** — refine the prompt and re-run

This is intentionally lighter than `skill-creator`'s eval flow — no formal grader, no benchmark.json. The point is qualitative review of real behavior, not quantitative scoring. If the user wants something more formal (with assertions, baselines, and benchmark comparisons), `skill-creator`'s eval infrastructure can be adapted — point them there.

---

## Improving an Existing Prompt

If the user comes in with an existing prompt, skip Phase 1 and go straight to:

1. **Read the prompt carefully**
2. **Run Phase 3 self-review** — surface issues
3. **Ask the user about their pain points** — "What's not working? What surprised you?"
4. **Map pain points to anti-patterns** — most prompt issues map cleanly to the patterns in `references/anti-patterns.md`
5. **Propose specific edits** — show the user the diff, explain the why
6. **Optionally run grill mode** for a deeper audit
7. **Iterate**

When improving a prompt, **don't rewrite for taste.** Make minimal, targeted edits that address actual problems. If the user's prompt is unconventional but works, leave it alone. The user's voice and structure matter — you're a copyeditor, not a ghostwriter.

---

## Communicating with the User

System prompts get written by people across a wide range of expertise — from experienced AI engineers to product managers to people building their first agent. Read context cues:

- **Beginners**: don't assume terms like "few-shot," "chain of thought," "tool calling," or "eagerness dial." Briefly define when first introduced. Don't dump the whole anatomy on them — show them the prompt and explain only the parts that matter.
- **Experienced users**: use the jargon, skip the explanations, let them drive. They probably want speed.
- **Somewhere in between**: most users. Explain unfamiliar terms once, then use them.

Always frame the interview as collaborative, not bureaucratic. You're helping them think through their agent — not running them through a form.

If the user gets frustrated or the interview is dragging, default to writing the best prompt you can with what you have and present it. They can iterate from there. A draft on the screen is more useful than a perfectly-scoped requirements doc.

---

## Reference files

Core guidance is in this `SKILL.md`. The `references/` directory has expanded material to load as needed:

- `references/prompt-anatomy.md` — section-by-section guide to the 10-part structure with examples
- `references/snippets.md` — battle-tested prompt snippets (eagerness dials, guardrails, anti-hallucination, parallel tool calls, etc.)
- `references/anti-patterns.md` — common pitfalls with BAD/GOOD examples

The `agents/` directory has subagent instructions:

- `agents/griller.md` — adversarial review for grill mode

---

## A note on the meta-loop

You are an agent reading a system prompt that was itself authored using these principles. If you spot something wrong with this skill — a contradiction, vague language, an outdated pattern — flag it to the user. Skills get better when their users improve them.

---
name: sentinel-workflow-research-spike
description: Time-boxed research spike workflow — define question, research, synthesize, output a decision. Use whenever the user says "spike", "research", "investigate", "compare options", "should we use X or Y", "how does Z work", "can we do X", "feasibility", "prototype", "explore", or otherwise asks for an exploration that produces a decision rather than code — even if they don't explicitly say "workflow". The Iron Law of this workflow is: NO CODE IN SPIKES. A spike produces a decision or recommendation. Time-box is one session, hard cap. Four steps — define, research, synthesize, output.
workflow: true
workflow-steps: 4
allowed-tools: Read Grep Glob Bash TodoWrite
origin: sentinel
---

# Research Spike Workflow

Investigating a question or technology before building. Time-boxed exploration that produces a decision or recommendation, not code.

This is a Sentinel workflow skill. When it activates, the `sentinel-workflow-runner` protocol drives execution — creates a run directory, checkpoints progress after each step, and supports resumption across sessions. You do not need to invoke the runner explicitly; it activates alongside this skill.

## Protocol summary

At the top of the workflow, create a new run:

```bash
RUN_ID=$(bash "${CLAUDE_PLUGIN_ROOT}/scripts/workflow-state.sh" start research-spike)
```

Before each numbered step, call `step-start`. After each step completes, call `step-complete` (with an artifact path if you produced one). After the final step, call `finish <run-id> completed`. On failure, call `step-fail` and follow the failure-handling rules in each section below.

Full protocol details: see `sentinel-workflow-runner` skill.

---

## When to Spike

- "Should we use X or Y?" -- technology comparison
- "How does Z work?" -- understanding external systems
- "Can we do X?" -- feasibility investigation
- "Why is X happening?" -- root cause research (before committing to a fix)

## 1. Define the Question

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/workflow-state.sh" step-start "$RUN_ID" 1 "Define the Question"
```

- [ ] Write a single, specific question the spike must answer
- [ ] Define success criteria: what output constitutes "done"?
- [ ] Set a time box (default: 1 hour / 1 session -- no multi-session spikes)
- [ ] Check `vault/investigations/` -- has this question been explored before?
- [ ] Check `vault/decisions/` -- was a decision already made about this?

**Write an artifact**: `vault/workflows/runs/$RUN_ID/artifacts/step-1-question.md` with the question, success criteria, time box, and any prior vault context.

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/workflow-state.sh" step-complete "$RUN_ID" 1 "artifacts/step-1-question.md"
```

## 2. Research (in priority order)

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/workflow-state.sh" step-start "$RUN_ID" 2 "Research"
```

### a. Codebase search (fastest, most relevant)
- Search for existing implementations of what you're investigating
- Read related architecture docs in `vault/architecture/`
- Check if there's already a pattern you can follow

### b. Library documentation
- Check vendor docs for API behavior, package usage, version-specific details
- Read official guides and migration notes

### c. GitHub search (proven implementations)
```bash
gh search repos "search term" --limit 5
gh search code "pattern" --limit 10
```
- Look for battle-tested implementations you can adopt or adapt
- Check stars, recent activity, and maintenance status

### d. Web research (broadest, least targeted)
- Search for recent articles and discussions
- Check platform developer docs

**Write an artifact**: `artifacts/step-2-research.md` with the notes and sources from each research pass.

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/workflow-state.sh" step-complete "$RUN_ID" 2 "artifacts/step-2-research.md"
```

## 3. Synthesize

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/workflow-state.sh" step-start "$RUN_ID" 3 "Synthesize"
```

- [ ] Summarize findings (not a brain dump -- structured conclusions)
- [ ] If comparing options, create a comparison table:

```markdown
| Criteria | Option A | Option B |
|----------|----------|----------|
| Complexity | Low | High |
| Maintenance | Active | Abandoned |
| Fits our patterns | Yes | Requires new pattern |
| Risk | Low | Medium |
```

- [ ] Make a recommendation with reasoning
- [ ] Identify unknowns that remain

**Write an artifact**: `artifacts/step-3-synthesis.md` with the comparison table (if applicable), the recommendation, and the remaining unknowns.

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/workflow-state.sh" step-complete "$RUN_ID" 3 "artifacts/step-3-synthesis.md"
```

## 4. Output

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/workflow-state.sh" step-start "$RUN_ID" 4 "Output"
```

### If the spike answers the question:
- [ ] Present recommendation to the user
- [ ] If it's an architectural decision, save to `vault/decisions/` as an ADR
- [ ] If it revealed a constraint, add to `vault/gotchas/`
- [ ] Proceed to implementation (use `sentinel-workflow-new-feature` or `sentinel-workflow-feature-improvement`)

### If the spike raises more questions:
- [ ] Document what was learned in `vault/investigations/`
- [ ] List the remaining questions
- [ ] Recommend next steps (another spike with narrower scope, or ask the user)

### If the spike hits a dead end:
- [ ] Document what was tried and why it doesn't work in `vault/investigations/`
- [ ] This is still valuable -- it prevents future sessions from repeating the work

**Write an artifact**: `artifacts/step-4-output.md` recording which branch applied (answered / raised more questions / dead end) and every vault entry touched.

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/workflow-state.sh" step-complete "$RUN_ID" 4 "artifacts/step-4-output.md"
bash "${CLAUDE_PLUGIN_ROOT}/scripts/workflow-state.sh" finish "$RUN_ID" completed
```

## Key Rules

- **Time-box strictly.** A spike that runs forever is just procrastination. 1 session max.
- **No code in spikes.** A spike produces a decision or recommendation. Implementation is a separate task.
- **Start with the codebase.** External research is slower and less relevant than understanding what you already have.
- **Document even negative results.** "X doesn't work because Y" saves future sessions hours.

#workflow #research #spike

# Research Spike Workflow

Investigating a question or technology before building. Time-boxed exploration that produces a decision or recommendation, not code.

## When to Spike

- "Should we use X or Y?" -- technology comparison
- "How does Z work?" -- understanding external systems
- "Can we do X?" -- feasibility investigation
- "Why is X happening?" -- root cause research (before committing to a fix)

## 1. Define the Question

- [ ] Write a single, specific question the spike must answer
- [ ] Define success criteria: what output constitutes "done"?
- [ ] Set a time box (default: 1 hour -- no multi-session spikes)
- [ ] Check `vault/investigations/` -- has this question been explored before?
- [ ] Check `vault/decisions/` -- was a decision already made about this?

## 2. Research (in priority order)

### a. Codebase search (fastest, most relevant)
- Search for existing implementations of what you're investigating
- Read related architecture docs in `vault/architecture/`
- Check if there's already a pattern you can follow

### b. Library documentation
- Check official docs for API behavior, package usage, version-specific details

### c. Code search (proven implementations)
- Search GitHub or other repositories for battle-tested implementations
- Check stars, recent activity, and maintenance status

### d. Web research (broadest, least targeted)
- Check relevant developer docs and articles
- Read recent discussions and blog posts

## 3. Synthesize

- [ ] Summarize findings (structured conclusions, not a brain dump)
- [ ] If comparing options, create a comparison table:

| Criteria | Option A | Option B |
|----------|----------|----------|
| Complexity | Low | High |
| Maintenance | Active | Abandoned |
| Fits our patterns | Yes | Requires new pattern |
| Risk | Low | Medium |

- [ ] Make a recommendation with reasoning
- [ ] Identify unknowns that remain

## 4. Output

### If the spike answers the question:
- [ ] Present recommendation to the user
- [ ] If it's an architectural decision, save to `vault/decisions/` as an ADR
- [ ] If it revealed a constraint, add to `vault/gotchas/`
- [ ] Proceed to implementation workflow

### If the spike raises more questions:
- [ ] Document what was learned in `vault/investigations/`
- [ ] List the remaining questions
- [ ] Recommend next steps

### If the spike hits a dead end:
- [ ] Document what was tried and why it doesn't work in `vault/investigations/`
- [ ] This is still valuable -- it prevents future sessions from repeating the work

## Key Rules

- **Time-box strictly.** A spike that runs forever is procrastination. 1 session max.
- **No code in spikes.** A spike produces a decision or recommendation. Implementation is a separate task.
- **Start with the codebase.** External research is slower and less relevant than understanding what you already have.
- **Document even negative results.** "X doesn't work because Y" saves future sessions hours.

#workflow #research #spike

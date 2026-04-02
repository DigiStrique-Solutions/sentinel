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
- [ ] Set a time box (default: 1 hour / 1 session -- no multi-session spikes)
- [ ] Check `vault/investigations/` -- has this question been explored before?
- [ ] Check `vault/decisions/` -- was a decision already made about this?

## 2. Research (in priority order)

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

## 3. Synthesize

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

## 4. Output

### If the spike answers the question:
- [ ] Present recommendation to the user
- [ ] If it's an architectural decision, save to `vault/decisions/` as an ADR
- [ ] If it revealed a constraint, add to `vault/gotchas/`
- [ ] Proceed to implementation (use `new-feature.md` or `feature-improvement.md`)

### If the spike raises more questions:
- [ ] Document what was learned in `vault/investigations/`
- [ ] List the remaining questions
- [ ] Recommend next steps (another spike with narrower scope, or ask the user)

### If the spike hits a dead end:
- [ ] Document what was tried and why it doesn't work in `vault/investigations/`
- [ ] This is still valuable -- it prevents future sessions from repeating the work

## Key Rules

- **Time-box strictly.** A spike that runs forever is just procrastination. 1 session max.
- **No code in spikes.** A spike produces a decision or recommendation. Implementation is a separate task.
- **Start with the codebase.** External research is slower and less relevant than understanding what you already have.
- **Document even negative results.** "X doesn't work because Y" saves future sessions hours.

#workflow #research #spike

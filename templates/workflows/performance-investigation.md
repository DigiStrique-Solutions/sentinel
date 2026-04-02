# Performance Investigation Workflow

For diagnosing and fixing slow endpoints, slow pages, or high resource usage. Different from bug-fix -- performance issues require measurement before hypothesizing.

## 1. Measure First (don't guess)

**Rule: No optimization without a baseline measurement.**

- [ ] Identify the specific operation that is slow
- [ ] Measure its current duration/resource usage with a profiler or timing instrumentation
- [ ] Record the baseline numbers (e.g., "P95 latency: 1200ms")

### Common measurement approaches:
- **Backend:** Add timing instrumentation around the suspected code path
- **Database:** Run `EXPLAIN ANALYZE` on slow queries
- **Frontend:** Use browser DevTools (Lighthouse, Network waterfall, React Profiler)
- **API:** Measure time-to-first-byte and total response time

## 2. Identify the Bottleneck

Common patterns:

| Symptom | Likely cause | Investigation |
|---------|-------------|---------------|
| Slow API response | N+1 queries, missing index | EXPLAIN ANALYZE, query count |
| Slow page load | Large bundle, blocking requests | Bundle analyzer, network waterfall |
| High memory | Large result sets loaded entirely | Check pagination, streaming |
| Slow writes | Missing indexes, lock contention | Database lock monitoring |

## 3. Hypothesize and Validate

- [ ] Form a hypothesis: "The slowness is caused by X because Y"
- [ ] Write a benchmark or test that measures the specific operation
- [ ] Validate the hypothesis with measurement (not intuition)
- [ ] If wrong, update `vault/investigations/` and try next hypothesis

## 4. Fix

- [ ] Make the targeted optimization
- [ ] Re-measure with the same benchmark
- [ ] Confirm improvement with specific numbers (e.g., "reduced from 1200ms to 180ms")
- [ ] Run full test suite to verify no behavioral regression

### Common fixes:
- **Database:** Add missing indexes, replace N+1 with joins, add pagination
- **Backend:** Cache frequently accessed data, use async I/O, stream results
- **Frontend:** Lazy load components, memoize computations, virtualize lists

## 5. Verify

- [ ] Baseline vs. after measurements documented
- [ ] Tests pass
- [ ] No behavioral changes (same inputs, same outputs, just faster)

## 6. Document

- [ ] Log findings in `vault/investigations/` (even if resolved)
- [ ] If a new performance constraint was discovered, add to `vault/gotchas/`
- [ ] Include before/after metrics

## Key Rules

- **Measure, don't guess.** The bottleneck is rarely where you think it is.
- **Optimize the bottleneck, not everything.** One fix to the slowest operation beats 10 micro-optimizations.
- **Performance fixes must not change behavior.** Same inputs, same outputs, just faster.
- **Document the numbers.** "It's faster now" is not acceptable. "Reduced P95 from 1200ms to 180ms" is.

#workflow #performance #investigation

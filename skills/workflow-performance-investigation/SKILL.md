---
name: sentinel-workflow-performance-investigation
description: Measurement-driven performance investigation workflow — baseline, bottleneck, hypothesis, fix, verify, document. Use whenever the user says "slow", "performance", "latency", "optimize", "too slow", "high memory", "N+1", "laggy", "LCP", "profile this", "why is this so slow", or otherwise signals a speed/resource problem — even if they don't explicitly say "workflow". The Iron Law of this workflow is: NO OPTIMIZATION WITHOUT A BASELINE MEASUREMENT. Measurements must include before/after numbers. Six steps — measure, identify bottleneck, hypothesize, fix, verify, document.
workflow: true
workflow-steps: 6
allowed-tools: Read Grep Glob Bash Edit Write MultiEdit TodoWrite
origin: sentinel
---

# Performance Investigation Workflow

For diagnosing and fixing slow endpoints, slow pages, or high resource usage. Different from bug-fix -- performance issues require measurement before hypothesizing.

This is a Sentinel workflow skill. When it activates, the `sentinel-workflow-runner` protocol drives execution — creates a run directory, checkpoints progress after each step, and supports resumption across sessions. You do not need to invoke the runner explicitly; it activates alongside this skill.

## Protocol summary

At the top of the workflow, create a new run:

```bash
RUN_ID=$(bash "${CLAUDE_PLUGIN_ROOT}/scripts/workflow-state.sh" start performance-investigation)
```

Before each numbered step, call `step-start`. After each step completes, call `step-complete` (with an artifact path if you produced one). After the final step, call `finish <run-id> completed`. On failure, call `step-fail` and follow the failure-handling rules in each section below.

Full protocol details: see `sentinel-workflow-runner` skill.

---

## 1. Measure First (don't guess)

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/workflow-state.sh" step-start "$RUN_ID" 1 "Measure First"
```

**Rule: No optimization without a baseline measurement.**

### Backend:
```bash
# Add timing to the specific function
import time
start = time.perf_counter()
# ... code ...
duration = time.perf_counter() - start
logger.info("operation_timing", operation="name", duration_ms=duration * 1000)
```

### Database queries:
```sql
-- Check slow queries
EXPLAIN ANALYZE SELECT ... FROM table WHERE ...;

-- Look for sequential scans on large tables
SELECT relname, seq_scan, seq_tup_read, idx_scan, idx_tup_fetch
FROM pg_stat_user_tables
ORDER BY seq_scan DESC;
```

### Frontend:
```bash
# Bundle size analysis
npm run build
# Check bundle analyzer output

# Lighthouse audit (run in browser)
# Focus on: LCP, FID, CLS, TTFB
```

**Write an artifact**: `vault/workflows/runs/$RUN_ID/artifacts/step-1-baseline.md` with the baseline numbers for the operation being investigated (P50/P95/memory/bundle size, whichever is relevant).

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/workflow-state.sh" step-complete "$RUN_ID" 1 "artifacts/step-1-baseline.md"
```

## 2. Identify the Bottleneck

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/workflow-state.sh" step-start "$RUN_ID" 2 "Identify the Bottleneck"
```

### Common patterns:

| Symptom | Likely cause | Investigation |
|---------|-------------|---------------|
| Slow API response | N+1 queries, missing index | `EXPLAIN ANALYZE`, check query count |
| Slow page load | Large bundle, blocking requests | Bundle analyzer, network waterfall |
| High memory | Large result sets loaded entirely | Check pagination, streaming |
| Slow external API | Third-party latency | Measure API call duration |

**Write an artifact**: `artifacts/step-2-bottleneck.md` identifying the single slowest operation and the evidence that points to it.

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/workflow-state.sh" step-complete "$RUN_ID" 2 "artifacts/step-2-bottleneck.md"
```

## 3. Hypothesize and Validate

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/workflow-state.sh" step-start "$RUN_ID" 3 "Hypothesize and Validate"
```

- [ ] Form a hypothesis: "The slowness is caused by X because Y"
- [ ] Write a benchmark test that measures the specific operation
- [ ] Validate the hypothesis with measurement (not intuition)
- [ ] If wrong, update `vault/investigations/` and try next hypothesis

**Write an artifact**: `artifacts/step-3-hypothesis.md` with the hypothesis statement, the benchmark, and the measurement that validated (or refuted) it.

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/workflow-state.sh" step-complete "$RUN_ID" 3 "artifacts/step-3-hypothesis.md"
```

## 4. Fix

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/workflow-state.sh" step-start "$RUN_ID" 4 "Fix"
```

- [ ] Make the targeted optimization
- [ ] Re-measure with the same benchmark
- [ ] Confirm improvement with specific numbers (e.g., "reduced from 1200ms to 180ms")
- [ ] Run full test suite to verify no behavioral regression

### Common fixes:

**Database:**
- Add missing indexes
- Replace N+1 with joined queries or batch loading
- Add pagination for large result sets
- Use eager loading for relationships

**Backend:**
- Cache frequently accessed, rarely changing data
- Move heavy computation to background tasks
- Use async I/O for external API calls
- Stream results instead of collecting then returning

**Frontend:**
- Lazy load heavy components (dynamic imports)
- Memoize expensive computations (`useMemo`, `useCallback`)
- Virtualize long lists
- Optimize re-renders (check React DevTools Profiler)

**Write an artifact**: `artifacts/step-4-fix.md` with the change made, before/after numbers from the benchmark, and the test suite result.

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/workflow-state.sh" step-complete "$RUN_ID" 4 "artifacts/step-4-fix.md"
```

## 5. Verify

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/workflow-state.sh" step-start "$RUN_ID" 5 "Verify"
```

- [ ] Baseline vs. after measurements documented
- [ ] Tests pass
- [ ] No behavioral changes (performance fix should not change output)

**Write an artifact**: `artifacts/step-5-verify.md` with the side-by-side baseline vs after numbers and the behavioral-parity evidence.

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/workflow-state.sh" step-complete "$RUN_ID" 5 "artifacts/step-5-verify.md"
```

## 6. Document

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/workflow-state.sh" step-start "$RUN_ID" 6 "Document"
```

- [ ] Log findings in `vault/investigations/` (even if resolved)
- [ ] If a new performance constraint is discovered, add to `vault/gotchas/`
- [ ] Include before/after metrics in the investigation file

**Write an artifact**: `artifacts/step-6-document.md` listing the investigation file path and any gotchas created.

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/workflow-state.sh" step-complete "$RUN_ID" 6 "artifacts/step-6-document.md"
bash "${CLAUDE_PLUGIN_ROOT}/scripts/workflow-state.sh" finish "$RUN_ID" completed
```

## Key Rules

- **Measure, don't guess.** The bottleneck is rarely where you think it is.
- **Optimize the bottleneck, not everything.** One fix to the slowest operation beats 10 micro-optimizations.
- **Performance fixes must not change behavior.** Same inputs, same outputs, just faster.
- **Document the numbers.** "It's faster now" is not acceptable. "Reduced P95 from 1200ms to 180ms" is.

#workflow #performance #investigation

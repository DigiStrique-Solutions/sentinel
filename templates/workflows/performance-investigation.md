# Performance Investigation Workflow

For diagnosing and fixing slow endpoints, slow pages, or high resource usage. Different from bug-fix -- performance issues require measurement before hypothesizing.

## 1. Measure First (don't guess)

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

## 2. Identify the Bottleneck

### Common patterns:

| Symptom | Likely cause | Investigation |
|---------|-------------|---------------|
| Slow API response | N+1 queries, missing index | `EXPLAIN ANALYZE`, check query count |
| Slow page load | Large bundle, blocking requests | Bundle analyzer, network waterfall |
| High memory | Large result sets loaded entirely | Check pagination, streaming |
| Slow external API | Third-party latency | Measure API call duration |

## 3. Hypothesize and Validate

- [ ] Form a hypothesis: "The slowness is caused by X because Y"
- [ ] Write a benchmark test that measures the specific operation
- [ ] Validate the hypothesis with measurement (not intuition)
- [ ] If wrong, update `vault/investigations/` and try next hypothesis

## 4. Fix

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

## 5. Verify

- [ ] Baseline vs. after measurements documented
- [ ] Tests pass
- [ ] No behavioral changes (performance fix should not change output)

## 6. Document

- [ ] Log findings in `vault/investigations/` (even if resolved)
- [ ] If a new performance constraint is discovered, add to `vault/gotchas/`
- [ ] Include before/after metrics in the investigation file

## Key Rules

- **Measure, don't guess.** The bottleneck is rarely where you think it is.
- **Optimize the bottleneck, not everything.** One fix to the slowest operation beats 10 micro-optimizations.
- **Performance fixes must not change behavior.** Same inputs, same outputs, just faster.
- **Document the numbers.** "It's faster now" is not acceptable. "Reduced P95 from 1200ms to 180ms" is.

#workflow #performance #investigation

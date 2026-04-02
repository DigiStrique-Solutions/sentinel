# Testing Requirements

## Minimum Test Coverage: 80%

Test Types (ALL required):
1. **Unit Tests** — Individual functions, utilities, components
2. **Integration Tests** — API endpoints, database operations, service interactions
3. **E2E Tests** — Critical user flows (framework chosen per language)

## Test-Driven Development

MANDATORY workflow:
1. Write test first (RED)
2. Run test — it should FAIL
3. Write minimal implementation (GREEN)
4. Run test — it should PASS
5. Refactor (IMPROVE)
6. Verify coverage (80%+)

## Every Failing Test Is Your Responsibility

- **Never dismiss a test failure as "pre-existing" or "not caused by my changes."**
- If a test was already failing before your changes, fix it anyway. Leaving broken tests is never acceptable.
- Diagnose the root cause, fix the code (or the test if the test is wrong), and confirm it passes before moving on.
- This applies to unit tests, integration tests, contract tests, E2E tests — all of them, always.

## What Constitutes a Real Test

A test MUST:
1. **Exercise the actual code under test** (not just mocks)
2. **Assert specific, meaningful outcomes** (not `is not None` or `is True`)
3. **Fail when the behavior it tests is broken** (delete the implementation — does the test fail?)
4. **Be independent of other tests** (no shared mutable state, no ordering dependency)

## Test Naming

Names should describe **behavior**, not implementation:

```
BAD:  test_get_campaigns_calls_api
GOOD: test_get_campaigns_returns_active_campaigns_for_org
```

## Mocking Guidelines

### Mock ONLY external boundaries:
- Database calls
- HTTP requests to external APIs
- File system operations
- Time/random (when determinism is needed)
- Third-party SDKs

### NEVER mock:
- The class/function under test
- Internal utility functions called by the code under test
- Pure functions (just call them with test inputs)

## Troubleshooting Test Failures

1. Check test isolation — does it depend on other tests?
2. Verify mocks are correct — are you mocking the right boundary?
3. Fix implementation, not tests (unless tests are wrong)
4. Use **tdd-guide** agent for structured assistance

---
name: tdd
description: Test-Driven Development workflow enforcement. Activates when writing new features, fixing bugs, or refactoring code. Enforces RED-GREEN-REFACTOR cycle with 80%+ coverage, edge case coverage, and anti-pattern avoidance.
origin: sentinel
---

# Test-Driven Development

This skill enforces disciplined TDD methodology. Tests are written BEFORE implementation, coverage targets are met, and anti-patterns are avoided.

## When to Activate

- Writing new features or functionality
- Fixing bugs (write a failing test that reproduces the bug first)
- Refactoring existing code (ensure safety net tests exist first)
- Adding API endpoints or service methods
- Creating new components or hooks

---

## The RED-GREEN-REFACTOR Cycle

### Step 1: Write ONE Failing Test (RED)

Write a single test that describes the expected behavior. Run it. It MUST fail.

```python
# This test should FAIL because create_user() does not exist yet
def test_create_user_returns_user_with_hashed_password():
    user = create_user(email="test@example.com", password="secret123")
    assert user.email == "test@example.com"
    assert user.password_hash != "secret123"
    assert len(user.password_hash) > 0
```

**Critical:** If the test passes before you write the implementation, the test is wrong. It is either testing a mock, asserting nothing meaningful, or the behavior already exists.

### Step 2: Run the Test -- Verify it FAILS

```bash
# Python
pytest tests/test_users.py::test_create_user_returns_user_with_hashed_password -x -v

# TypeScript
npx vitest run src/users.test.ts -t "create user"

# JavaScript
npm test -- --testPathPattern="users" --testNamePattern="create user"
```

The test must fail for the **right reason** -- the function does not exist or does not produce the expected result. Not a setup error, import error, or syntax error.

### Step 3: Write Minimal Implementation (GREEN)

Write the **minimum** code to make the test pass. Nothing more.

```python
def create_user(email: str, password: str) -> User:
    password_hash = bcrypt.hashpw(password.encode(), bcrypt.gensalt()).decode()
    return User(email=email, password_hash=password_hash)
```

### Step 4: Run the Test -- Verify it PASSES

```bash
pytest tests/test_users.py::test_create_user_returns_user_with_hashed_password -x -v
```

### Step 5: Refactor (IMPROVE)

Improve the code without changing behavior. Tests must stay green.

- Remove duplication
- Improve naming
- Extract helper functions
- Optimize performance
- Enhance readability

Run the full test suite after refactoring to catch unintended regressions.

### Step 6: Repeat

Go back to Step 1 with the next test case. One test at a time.

---

## Coverage Targets

| Metric | Target |
|--------|--------|
| Line coverage | 80%+ |
| Branch coverage | 80%+ |
| Function coverage | 80%+ |
| Statement coverage | 80%+ |

### Measuring Coverage

```bash
# Python
pytest --cov=src --cov-report=term-missing tests/

# TypeScript/JavaScript
npx vitest run --coverage
# or
npx jest --coverage
```

### What 80% Means

80% is the floor, not the ceiling. Critical paths (auth, payments, data mutations) should approach 100%. Utility code and simple getters can be lower. The average across the module should be 80%+.

---

## Edge Case Checklist

Every function should be tested with these categories:

### Input Boundaries
- [ ] **Empty** -- empty string, empty array, empty object
- [ ] **None/Null/Undefined** -- null inputs where applicable
- [ ] **Zero** -- numeric zero, including as divisor
- [ ] **Negative** -- negative numbers where positive is expected
- [ ] **Boundary values** -- min, max, off-by-one (0, 1, MAX_INT-1, MAX_INT)
- [ ] **Large inputs** -- very long strings, very large arrays

### Type Edge Cases
- [ ] **Special characters** -- Unicode, emoji, SQL injection characters, HTML entities
- [ ] **Whitespace** -- leading/trailing spaces, tabs, newlines, empty-looking strings
- [ ] **Type coercion** -- "0" vs 0, "false" vs false, "" vs null

### Error Conditions
- [ ] **Network failures** -- timeout, connection refused, DNS failure
- [ ] **Database errors** -- connection lost, constraint violation, deadlock
- [ ] **Permission denied** -- unauthorized access, expired tokens
- [ ] **Resource exhaustion** -- disk full, memory limit, rate limit exceeded
- [ ] **Concurrent access** -- race conditions, double-submit

---

## When to Mock vs Use Real Dependencies

### Use Real Dependencies When

- The dependency is fast and deterministic (pure functions, in-memory data structures)
- You are writing integration tests that specifically test the interaction
- The dependency is a local database with test fixtures
- The dependency is cheap to set up and tear down

### Mock When

- The dependency is external and unreliable (third-party APIs, payment processors)
- The dependency is slow (network calls, disk I/O)
- The dependency has side effects you cannot undo (sending emails, charging cards)
- You need to simulate error conditions that are hard to reproduce
- You need deterministic behavior from non-deterministic sources (time, randomness)

### Mock Boundary

```
Your Code  -->  [Mock Boundary]  -->  External World
                                      - HTTP APIs
                                      - Databases (for unit tests)
                                      - File system
                                      - Time/random
                                      - Third-party SDKs
```

Mock at the boundary. Never mock your own code.

---

## TDD Anti-Patterns

### 1. Writing Tests After Implementation

This defeats the purpose of TDD. Tests written after code tend to test the implementation rather than the behavior. They pass by construction and fail to catch real bugs.

**Remedy:** Discipline. Write the test first. Run it. Watch it fail. Then implement.

### 2. Testing Mocks Instead of Code

If your test creates a mock, calls the mock, and asserts the mock returned what you told it to, you have tested nothing.

**Remedy:** Mock only external dependencies. Call the real function under test.

### 3. Writing All Tests at Once

Writing 20 tests before any implementation leads to analysis paralysis and tests that are disconnected from the actual design.

**Remedy:** One test at a time. RED-GREEN-REFACTOR. Repeat.

### 4. Skipping the RED Step

If you never see the test fail, you do not know it can fail. A test that cannot fail provides zero value.

**Remedy:** Always run the test before implementing. Verify it fails for the right reason.

### 5. Testing Implementation Details

Testing internal state, private methods, or specific function call sequences makes tests brittle. They break on refactoring even when behavior is preserved.

**Remedy:** Test observable behavior. What goes in, what comes out, what side effects occur.

### 6. Ignoring the REFACTOR Step

Skipping refactoring leads to passing but messy code. The refactor step is where code quality improves.

**Remedy:** After every GREEN, ask: can this be simpler, clearer, or better named? Refactor with confidence because tests protect you.

---

## Test Structure

### Arrange-Act-Assert (AAA)

```python
def test_calculate_discount_applies_percentage():
    # Arrange
    price = Decimal("100.00")
    discount_percent = 20

    # Act
    result = calculate_discount(price, discount_percent)

    # Assert
    assert result == Decimal("80.00")
```

### One Behavior Per Test

```python
# GOOD -- each test verifies one behavior
def test_login_succeeds_with_valid_credentials(): ...
def test_login_fails_with_wrong_password(): ...
def test_login_fails_with_nonexistent_email(): ...
def test_login_locks_account_after_five_failures(): ...

# BAD -- one test verifies everything
def test_login(): ...  # 50 lines checking all cases
```

### Descriptive Test Names

Test names should describe the scenario and expected outcome:

```
test_<function>_<scenario>_<expected_result>

test_create_user_with_duplicate_email_raises_conflict_error
test_calculate_tax_with_zero_amount_returns_zero
test_parse_date_with_invalid_format_raises_value_error
```

---

## Workflow Summary

```
1. Pick the next behavior to implement
2. Write ONE failing test (RED)
3. Run it -- verify it FAILS
4. Write minimal code to pass (GREEN)
5. Run it -- verify it PASSES
6. Refactor -- keep tests green (IMPROVE)
7. Run full suite -- verify no regressions
8. Repeat from step 1
9. Check coverage -- verify 80%+
```

---
name: quality-patterns
description: Universal anti-patterns and test standards. Activates when reviewing test quality, writing tests, or auditing code for common mistakes. Covers the 10 most damaging anti-patterns with BAD/GOOD examples, test validity criteria, and mocking guidelines.
origin: sentinel
---

# Quality Patterns

Universal anti-patterns to avoid and test standards to follow. These patterns are language-agnostic in principle, with examples in Python and TypeScript for concreteness.

## When to Activate

- Writing or reviewing tests
- Auditing code quality
- Reviewing pull requests
- Investigating test failures
- Setting up test infrastructure for a new module

---

## What Constitutes a Real Test

A test MUST satisfy all four criteria:

1. **Exercises the actual code under test** -- not just mocks or stubs
2. **Asserts specific, meaningful outcomes** -- not `is not None` or `is True`
3. **Fails when the behavior it tests is broken** -- delete the implementation; does the test fail?
4. **Is independent of other tests** -- no shared mutable state, no ordering dependency

If a test fails any of these criteria, it provides false confidence and should be rewritten.

---

## The 10 Anti-Patterns

### 1. Testing the Mock, Not the Code

**BAD** -- test mocks the function under test and asserts the mock was called:
```python
async def test_classifier():
    classifier = MagicMock()
    classifier.classify.return_value = ClassificationResult(needs_planning=True)
    result = await classifier.classify("anything")
    assert result.needs_planning is True
```
This test passes even if the real classifier is deleted from the codebase.

**GOOD** -- test calls the real function with controlled inputs:
```python
async def test_classify_multi_step_query_needs_planning():
    classifier = ComplexityClassifier()
    result = await classifier.classify("Audit my records and create a report")
    assert result.needs_planning is True
    assert result.estimated_steps >= 2
```

### 2. Assert True / Assert Not None

**BAD** -- passes for any non-None value:
```python
result = await service.get_items(org_id)
assert result is not None
```

**GOOD** -- asserts specific, meaningful outcomes:
```python
result = await service.get_items(org_id)
assert len(result) == 3
assert result[0].status == "ACTIVE"
assert result[0].org_id == org_id
```

### 3. Copying Implementation Into Test

**BAD** -- test reimplements the business logic:
```python
def test_calculate_rate():
    clicks, impressions = 50, 1000
    expected = clicks / impressions * 100  # duplicated logic
    assert calculate_rate(clicks, impressions) == expected
```

**GOOD** -- test uses independently-derived expected values:
```python
def test_calculate_rate():
    assert calculate_rate(50, 1000) == 5.0   # known correct answer
    assert calculate_rate(0, 1000) == 0.0
    assert calculate_rate(50, 0) == 0.0       # edge case: division by zero
```

### 4. Testing Only Happy Path

**BAD** -- one test with valid inputs:
```python
def test_create_item():
    result = create_item(name="Test", budget=100)
    assert result.id is not None
```

**GOOD** -- tests for valid, invalid, edge cases, and error conditions:
```python
def test_create_item_valid():
    result = create_item(name="Test", budget=100)
    assert result.id is not None
    assert result.name == "Test"

def test_create_item_empty_name_raises():
    with pytest.raises(ValueError, match="name cannot be empty"):
        create_item(name="", budget=100)

def test_create_item_negative_budget_raises():
    with pytest.raises(ValueError, match="budget must be positive"):
        create_item(name="Test", budget=-1)

def test_create_item_zero_budget_raises():
    with pytest.raises(ValueError, match="budget must be positive"):
        create_item(name="Test", budget=0)
```

### 5. Overly Broad Exception Handling in Tests

**BAD** -- swallowing errors to make tests pass:
```python
def test_flaky_api_call():
    try:
        result = api.fetch_data()
        assert result.status == "ok"
    except Exception:
        pass  # "handles" intermittent failures
```

**GOOD** -- tests must be deterministic. Mock the external dependency:
```python
def test_api_call_success(mock_http):
    mock_http.get("/data").respond(200, json={"status": "ok"})
    result = api.fetch_data()
    assert result.status == "ok"

def test_api_call_failure(mock_http):
    mock_http.get("/data").respond(500)
    with pytest.raises(ApiError, match="failed to fetch"):
        api.fetch_data()
```

### 6. Silencing Errors Instead of Fixing Them

**BAD** -- wrapping in try/except and returning a default:
```python
def get_metrics(item_id: str):
    try:
        return metrics_service.fetch(item_id)
    except Exception:
        return {}  # silently returns empty on any error
```

**GOOD** -- handle specific errors, let unexpected ones propagate:
```python
def get_metrics(item_id: str):
    try:
        return metrics_service.fetch(item_id)
    except MetricsNotFoundError:
        logger.info("no_metrics_found", item_id=item_id)
        return {}
    except MetricsServiceError as e:
        logger.error("metrics_fetch_failed", item_id=item_id, error=str(e))
        raise
```

### 7. Adding Parameters to Bypass Logic

**BAD** -- adding escape hatches instead of fixing the real problem:
```python
def process_item(item, skip_validation=False, force=False, ignore_limit=False):
    if not skip_validation:
        validate(item)
    ...
```

**GOOD** -- fix the validation or adjust the input:
```python
def process_item(item: Item):
    validate(item)  # always validates
    ...
```
If validation fails for a legitimate case, fix the validation rules -- do not bypass them.

### 8. Duplicating Code Instead of Abstracting

**BAD** -- copy-pasting a function and changing two lines:
```python
def get_items_from_source_a(account_id): ...   # 40 lines
def get_items_from_source_b(account_id): ...   # 39 nearly identical lines
```

**GOOD** -- parameterize or use strategy pattern:
```python
def get_items(account_id: str, source: DataSource) -> list[Item]:
    client = source.get_client()
    return client.list_items(account_id)
```

### 9. Using Any/Unknown Types to Avoid Type Errors

**BAD** -- casting to `Any` to silence the type checker:
```python
result: Any = service.get_data()  # avoids dealing with the actual type
```

**GOOD** -- understand and fix the type mismatch:
```python
result: ItemMetrics = service.get_data()
# If the type does not exist yet, create it
```

### 10. Hardcoding Values for "This One Case"

**BAD** -- special-casing specific IDs:
```python
if org_id == "org_3AXJh6Gv0tgaIJmHDfindZekbTV":
    return special_handling()
```

**GOOD** -- use configuration, feature flags, or proper conditional logic:
```python
if org.has_capability(Capability.ADVANCED_REPORTING):
    return advanced_reporting(org)
```

---

## Mocking Guidelines

### Mock ONLY External Boundaries

Mock these:
- Database calls (use fixtures, factory functions, or test database)
- HTTP requests to external APIs
- File system operations
- Time and randomness (when determinism is needed)
- Third-party SDKs

### NEVER Mock

- The class or function under test
- Internal utility functions called by the code under test
- Data class or model constructors
- Pure functions (just call them with test inputs)

### Mock Correctly

```python
# WRONG -- mocking the function you are testing
@patch("src.services.item_service.ItemService.get_items")
async def test_get_items(mock_get):
    mock_get.return_value = [...]
    result = await ItemService().get_items("org_123")
    # This tests nothing

# RIGHT -- mocking the external dependency the function calls
@patch("src.services.item_service.ExternalApiClient")
async def test_get_items(mock_client):
    mock_client.return_value.list_items.return_value = [item_fixture()]
    service = ItemService(client=mock_client.return_value)
    result = await service.get_items("org_123")
    assert len(result) == 1
    assert result[0].name == "Test Item"
```

---

## Test Naming Conventions

Test names should describe **behavior**, not implementation:

```python
# BAD -- describes implementation
def test_get_items_calls_api()
def test_process_returns_dict()

# GOOD -- describes behavior
def test_get_items_returns_active_items_for_org()
def test_process_rejects_expired_item_with_error()
def test_classify_marks_multi_step_query_as_planning_needed()
```

---

## When You Are Tempted

If you feel the urge to use any anti-pattern, STOP and ask yourself:

1. Am I doing this because it is correct, or because it is easier?
2. Will this create tech debt someone has to clean up later?
3. Would a senior engineer reviewing this PR approve this approach?

If the answer to #1 is "easier" or #2 is "yes", discuss with the user before proceeding.

# Anti-Patterns

Claude Code MUST avoid all patterns listed here. Before writing code, review this list. If you catch yourself doing any of these, stop and use the correct approach.

---

## Testing Anti-Patterns

### 1. Testing the Mock, Not the Code

**BAD** -- test mocks the function under test and asserts the mock was called:
```python
async def test_service():
    service = MagicMock()
    service.process.return_value = Result(success=True)
    result = await service.process("anything")
    assert result.success is True
```
This test passes even if the service is deleted.

**GOOD** -- test calls the real function with controlled inputs:
```python
async def test_process_valid_input():
    service = ItemService()
    result = await service.process("valid input")
    assert result.success is True
    assert result.item_count >= 1
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
    count, total = 50, 1000
    expected = count / total * 100  # duplicated logic
    assert calculate_rate(count, total) == expected
```

**GOOD** -- test uses independently-derived expected values:
```python
def test_calculate_rate():
    assert calculate_rate(50, 1000) == 5.0  # known correct answer
    assert calculate_rate(0, 1000) == 0.0
    assert calculate_rate(50, 0) == 0.0     # edge case: division by zero
```

### 4. Testing Only Happy Path

**BAD** -- one test with valid inputs:
```python
def test_create_item():
    result = create_item(name="Test", quantity=100)
    assert result.id is not None
```

**GOOD** -- tests for valid, invalid, edge cases, and error conditions:
```python
def test_create_item_valid():
    result = create_item(name="Test", quantity=100)
    assert result.id is not None
    assert result.name == "Test"

def test_create_item_empty_name_raises():
    with pytest.raises(ValueError, match="name cannot be empty"):
        create_item(name="", quantity=100)

def test_create_item_negative_quantity_raises():
    with pytest.raises(ValueError, match="quantity must be positive"):
        create_item(name="Test", quantity=-1)

def test_create_item_zero_quantity():
    with pytest.raises(ValueError, match="quantity must be positive"):
        create_item(name="Test", quantity=0)
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

---

## Code Anti-Patterns

### 6. Silencing Errors Instead of Fixing Them

**BAD** -- wrapping in try/except and returning a default:
```python
def get_item_metrics(item_id: str):
    try:
        return metrics_service.fetch(item_id)
    except Exception:
        return {}  # silently returns empty on any error
```

**GOOD** -- handle specific errors, let unexpected ones propagate:
```python
def get_item_metrics(item_id: str):
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
def process_item(item, skip_validation=False, force=False, ignore_limits=False):
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
If validation fails for a legitimate case, fix the validation rules -- don't bypass them.

### 8. Duplicating Code Instead of Abstracting

**BAD** -- copy-pasting a function and changing 2 lines:
```python
def get_active_items(org_id): ...    # 40 lines
def get_archived_items(org_id): ...  # 39 nearly identical lines
```

**GOOD** -- parameterize or use strategy pattern:
```python
def get_items(org_id: str, status: ItemStatus) -> list[Item]:
    return repository.find_by_org_and_status(org_id, status)
```

### 9. Using Any/Unknown Types to Avoid Type Errors

**BAD** -- casting to `Any` to silence type checker:
```python
result: Any = service.get_data()  # avoids dealing with the actual type
```

**GOOD** -- understand and fix the type mismatch:
```python
result: ItemMetrics = service.get_data()
# If the type doesn't exist yet, create it
```

### 10. Hardcoding Values for "This One Case"

**BAD** -- special-casing specific IDs:
```python
if org_id == "org_3AXJh6Gv0tgaIJmHDfindZekbTV":
    return special_handling()
```

**GOOD** -- use configuration, feature flags, or proper conditional logic:
```python
if org.has_feature(Feature.ADVANCED_REPORTING):
    return advanced_reporting(org)
```

---

## When You're Tempted

If you feel the urge to use any anti-pattern, STOP and ask yourself:
1. Am I doing this because it's correct, or because it's easier?
2. Will this create tech debt someone has to clean up later?
3. Would a senior engineer reviewing this PR approve this approach?

If the answer to #1 is "easier" or #2 is "yes", discuss with the user before proceeding.

#quality #anti-patterns

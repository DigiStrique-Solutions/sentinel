# Test Standards

## What Constitutes a Real Test

A test MUST:
1. **Exercise the actual code under test** (not just mocks)
2. **Assert specific, meaningful outcomes** (not `is not None` or `is True`)
3. **Fail when the behavior it tests is broken** (delete the implementation -- does the test fail?)
4. **Be independent of other tests** (no shared mutable state, no ordering dependency)

## Test Structure Per File

Each test file should cover:
- **Unit tests** for individual functions (fast, no I/O)
- **Edge case tests** (empty inputs, None values, boundary conditions, zero, negative)
- **Error case tests** (invalid inputs, network failures, DB errors, permission denied)
- **Integration tests** for service methods (may use DB fixtures or real dependencies)

## Good Test Example (Python)

```python
@pytest.mark.asyncio
async def test_process_returns_enriched_result_for_valid_input():
    """Valid inputs should produce enriched results with metadata."""
    processor = DataProcessor()

    result = await processor.process("valid-input-id", options={"enrich": True})

    assert result.status == "completed"
    assert result.item_count >= 1
    assert result.metadata is not None
    assert "processed_at" in result.metadata
```

**Why this is good:**
- Descriptive name states the behavior under test
- Arranges real objects (not mocking the processor itself)
- Acts with a realistic input
- Asserts specific properties with meaningful conditions
- Would fail if processing logic broke

## Bad Test Example (Python)

```python
async def test_processor():
    processor = MagicMock()
    processor.process.return_value = Result(status="completed")

    result = await processor.process("anything")

    assert result is not None
    assert result.status == "completed"
```

**Why this is bad:**
- Tests the mock, not the processor
- `assert result is not None` is meaningless (mock always returns something)
- Would pass even if `DataProcessor` was completely deleted from codebase
- Name is generic, does not describe behavior

## Good Test Example (TypeScript)

```typescript
describe('useFormState', () => {
  it('should transition from IDLE to SUBMITTING when submitting', async () => {
    const { result } = renderHook(() => useFormState({ formId: 'test-123' }));

    act(() => {
      result.current.submit({ name: 'Test' });
    });

    expect(result.current.state).toBe('SUBMITTING');
    expect(result.current.pendingData).toEqual({ name: 'Test' });
  });

  it('should handle empty submission gracefully', () => {
    const { result } = renderHook(() => useFormState({ formId: 'test-123' }));

    act(() => {
      result.current.submit({});
    });

    expect(result.current.state).toBe('IDLE');
    expect(result.current.error).toBeNull();
  });
});
```

## Mocking Guidelines

### Mock ONLY external boundaries:
- Database calls (use fixtures, factory functions, or test DB)
- HTTP requests to external APIs
- File system operations
- Time/random (when determinism is needed)
- Third-party SDKs

### NEVER mock:
- The class/function under test
- Internal utility functions called by the code under test
- Pydantic/dataclass constructors
- Pure functions (just call them with test inputs)

### Mock Correctly:
```python
# WRONG -- mocking the function you're testing
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

## Naming Convention

Test names should describe **behavior**, not implementation:

```python
# BAD -- describes implementation
def test_get_items_calls_api()
def test_process_returns_dict()

# GOOD -- describes behavior
def test_get_items_returns_active_items_for_org()
def test_process_rejects_expired_item_with_error()
```

## Coverage Requirements

- Minimum 80% coverage for new code
- Python: `pytest tests/ --cov=src --cov-report=term-missing`
- TypeScript: `npm test -- --coverage` or `yarn test --coverage`

## Common Test Patterns

### Singleton Registry Teardown
Always reset singleton instances in test fixtures:
```python
@pytest.fixture(autouse=True)
def reset_singletons():
    yield
    Registry._instance = None
```

### Timing Assertions
Never assert `duration_ms > 0` -- events can share the same millisecond:
```python
assert metrics.duration_ms >= 0
assert metrics.started_at_ms > 0
assert metrics.ended_at_ms >= metrics.started_at_ms
```

### Bound Method Identity
Store bound method references for subscriber patterns:
```python
handler = received.append  # Store once
bus.add_subscriber(handler)
bus.remove_subscriber(handler)  # Same object -- works
```

#quality #testing

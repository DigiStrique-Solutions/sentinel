---
paths:
  - "**/*.py"
  - "**/*.pyi"
---
# Python Testing

> This file extends [common/testing.md](../common/testing.md) with Python-specific content.

## Framework

Use **pytest** as the testing framework.

## Coverage

```bash
pytest --cov=src --cov-report=term-missing
```

Target: 80% minimum for new code.

## Test Organization

Use `pytest.mark` for test categorization:

```python
import pytest

@pytest.mark.unit
def test_calculate_total():
    assert calculate_total([10, 20, 30]) == 60

@pytest.mark.integration
async def test_database_query():
    result = await repo.find_by_id("test-123")
    assert result.name == "Test"
```

## Fixtures

Use fixtures for test setup — not setUp/tearDown methods:

```python
@pytest.fixture
def sample_user():
    return User(name="Test", email="test@example.com")

def test_user_display_name(sample_user):
    assert sample_user.display_name == "Test"
```

## Parametrization

Use `@pytest.mark.parametrize` for testing multiple inputs:

```python
@pytest.mark.parametrize("input_val,expected", [
    (0, 0),
    (1, 1),
    (10, 55),
    (-1, ValueError),
])
def test_fibonacci(input_val, expected):
    if isinstance(expected, type) and issubclass(expected, Exception):
        with pytest.raises(expected):
            fibonacci(input_val)
    else:
        assert fibonacci(input_val) == expected
```

## Async Tests

```python
import pytest

@pytest.mark.asyncio
async def test_async_fetch():
    result = await service.fetch_data("test-id")
    assert result.status == "ok"
    assert len(result.items) > 0
```

## Singleton Teardown

Always reset singleton instances in test fixtures:

```python
@pytest.fixture(autouse=True)
def reset_singletons():
    yield
    Registry._instance = None
```

## Reference

See skill: `python-testing` for detailed pytest patterns and fixtures.

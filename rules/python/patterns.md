---
paths:
  - "**/*.py"
  - "**/*.pyi"
---
# Python Patterns

> This file extends [common/patterns.md](../common/patterns.md) with Python-specific content.

## Protocol (Structural Subtyping)

Use `Protocol` for duck-typed interfaces:

```python
from typing import Protocol

class Repository(Protocol):
    def find_by_id(self, id: str) -> dict | None: ...
    def save(self, entity: dict) -> dict: ...
```

## Dataclasses as DTOs

```python
from dataclasses import dataclass

@dataclass
class CreateUserRequest:
    name: str
    email: str
    age: int | None = None
```

## Context Managers

Use context managers (`with` statement) for resource management:

```python
from contextlib import contextmanager

@contextmanager
def database_transaction(session):
    try:
        yield session
        session.commit()
    except Exception:
        session.rollback()
        raise
```

## Generators

Use generators for lazy evaluation and memory-efficient iteration:

```python
def paginate(items: list, page_size: int = 100):
    for i in range(0, len(items), page_size):
        yield items[i:i + page_size]
```

## Decorators

Use decorators for cross-cutting concerns:

```python
import functools
import time

def timed(func):
    @functools.wraps(func)
    def wrapper(*args, **kwargs):
        start = time.perf_counter()
        result = func(*args, **kwargs)
        duration = time.perf_counter() - start
        logger.info("timing", func=func.__name__, duration_ms=duration * 1000)
        return result
    return wrapper
```

## API Response Envelope

```python
from dataclasses import dataclass
from typing import Generic, TypeVar

T = TypeVar("T")

@dataclass(frozen=True)
class ApiResponse(Generic[T]):
    success: bool
    data: T | None = None
    error: str | None = None
    meta: dict | None = None
```

## Reference

See skill: `python-patterns` for comprehensive patterns including concurrency and package organization.

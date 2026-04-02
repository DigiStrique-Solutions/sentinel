---
paths:
  - "**/*.py"
  - "**/*.pyi"
---
# Python Coding Style

> This file extends [common/coding-style.md](../common/coding-style.md) with Python-specific content.

## Standards

- Follow **PEP 8** conventions
- Use **type annotations** on all function signatures and return types
- Docstrings in imperative mood: "Return" not "Returns", "Fetch" not "Fetches"
- Use `r"""` for docstrings containing backslashes (ruff D301)

## Immutability

Prefer immutable data structures:

```python
from dataclasses import dataclass

@dataclass(frozen=True)
class User:
    name: str
    email: str

from typing import NamedTuple

class Point(NamedTuple):
    x: float
    y: float
```

> **Override**: Idiomatic Python sometimes uses mutable objects (e.g., list comprehensions building a result). Mutation of *local* temporaries is acceptable; mutation of *shared state* or *function arguments* is not.

## Formatting

- **ruff** for linting and formatting (preferred)
- **black** for code formatting (alternative)
- **isort** for import sorting

## Error Handling

Use specific exception types:

```python
# WRONG: Bare except or overly broad
try:
    result = fetch_data(id)
except Exception:
    return {}

# CORRECT: Specific exceptions with context
try:
    result = fetch_data(id)
except NotFoundError:
    logger.info("not_found", id=id)
    return None
except ConnectionError as e:
    logger.error("fetch_failed", id=id, error=str(e))
    raise
```

## Reference

See skill: `python-patterns` for comprehensive Python idioms and patterns.

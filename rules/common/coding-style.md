# Coding Style

## Immutability (CRITICAL)

ALWAYS create new objects, NEVER mutate existing ones:

```
// Pseudocode
WRONG:  modify(original, field, value) → changes original in-place
CORRECT: update(original, field, value) → returns new copy with change
```

Rationale: Immutable data prevents hidden side effects, makes debugging easier, and enables safe concurrency.

> **Language note**: This rule may be overridden by language-specific rules for languages where this pattern is not idiomatic.

## File Organization

MANY SMALL FILES > FEW LARGE FILES:
- High cohesion, low coupling
- 200-400 lines typical, 800 max
- Extract utilities from large modules
- Organize by feature/domain, not by type

## Function Size

- Functions under 50 lines
- Single responsibility per function
- Extract complex conditionals into named helper functions
- No deep nesting (>4 levels) — flatten with early returns or extraction

## Error Handling

ALWAYS handle errors comprehensively:
- Handle errors explicitly at every level
- Provide user-friendly error messages in UI-facing code
- Log detailed error context on the server side
- Never silently swallow errors
- Handle specific errors, let unexpected ones propagate

## Input Validation

ALWAYS validate at system boundaries:
- Validate all user input before processing
- Use schema-based validation where available
- Fail fast with clear error messages
- Never trust external data (API responses, user input, file content)

## Naming

- Use descriptive, intention-revealing names
- Boolean variables: prefix with `is`, `has`, `should`, `can`
- Functions: use verbs (`calculate`, `validate`, `fetch`, `render`)
- Constants: UPPER_SNAKE_CASE
- Avoid abbreviations unless universally understood (`id`, `url`, `api`)

## Code Quality Checklist

Before marking work complete:
- [ ] Code is readable and well-named
- [ ] Functions are small (<50 lines)
- [ ] Files are focused (<800 lines)
- [ ] No deep nesting (>4 levels)
- [ ] Proper error handling
- [ ] No hardcoded values (use constants or config)
- [ ] No mutation (immutable patterns used)
- [ ] No dead code, commented-out code, or debug statements

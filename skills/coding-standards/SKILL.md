---
name: coding-standards
description: Universal coding standards and best practices. Activates when writing new code, reviewing code quality, refactoring, or enforcing naming, formatting, or structural consistency. Covers immutability, file organization, error handling, input validation, and naming conventions.
origin: sentinel
---

# Coding Standards

Universal coding standards applicable across all projects and languages. These are non-negotiable quality standards.

## When to Activate

- Writing new code in any language
- Reviewing code for quality and maintainability
- Refactoring existing code
- Setting up or enforcing project conventions
- Onboarding contributors to code quality standards

---

## 1. Immutability (CRITICAL)

ALWAYS create new objects. NEVER mutate existing ones.

### Why

Immutable data prevents hidden side effects, makes debugging easier, enables safe concurrency, and makes state changes explicit and traceable.

### Examples

```typescript
// WRONG: mutates the original object
user.name = "New Name";
items.push(newItem);
delete config.oldKey;

// CORRECT: creates new objects
const updatedUser = { ...user, name: "New Name" };
const updatedItems = [...items, newItem];
const { oldKey, ...updatedConfig } = config;
```

```python
# WRONG: mutates the original
user["name"] = "New Name"
items.append(new_item)

# CORRECT: creates new objects
updated_user = {**user, "name": "New Name"}
updated_items = [*items, new_item]
```

### When Mutation Is Acceptable

- Performance-critical hot paths with measured benchmarks justifying the mutation
- Builder pattern during object construction (before the object is "published")
- Local variables that never escape the function scope

When mutating deliberately, add a comment explaining why:
```python
# Deliberately mutating for performance: this array has 100K+ elements
# and copying would cause GC pressure in the hot loop
items.append(new_item)
```

---

## 2. File Organization

### Many Small Files > Few Large Files

| Metric | Target | Maximum |
|--------|--------|---------|
| Lines per file | 200-400 | 800 |
| Functions per file | 5-15 | 25 |
| Exports per file | 1-5 | 10 |

### Principles

- **High cohesion:** everything in a file should relate to a single concept
- **Low coupling:** files should depend on abstractions, not each other's internals
- **Organize by feature/domain**, not by type (prefer `users/service.py` over `services/user_service.py`)

### When a File Is Too Large

Signs a file needs splitting:
- Multiple unrelated functions in the same file
- Scrolling required to find related code
- Multiple developers frequently editing the same file (merge conflicts)
- File has more than 800 lines

How to split:
1. Identify cohesive groups of functions
2. Extract each group into its own file
3. Create an index/barrel file if needed for backward compatibility
4. Update imports across the codebase
5. Run tests to verify nothing broke

---

## 3. Function Size

### Target: Under 50 Lines

A function that exceeds 50 lines is doing too much. Split it.

### How to Split Large Functions

```python
# BAD: 80-line function doing everything
def process_order(order):
    # validate (15 lines)
    # calculate totals (20 lines)
    # apply discounts (15 lines)
    # save to database (10 lines)
    # send notification (10 lines)
    # update inventory (10 lines)
    ...

# GOOD: orchestrator with focused helpers
def process_order(order: Order) -> ProcessedOrder:
    validated = validate_order(order)
    totals = calculate_totals(validated)
    discounted = apply_discounts(totals)
    saved = save_order(discounted)
    notify_order_placed(saved)
    update_inventory(saved)
    return saved
```

### Signs a Function Is Too Long

- Multiple levels of indentation (more than 3-4 levels)
- Multiple blank lines separating "sections" within the function
- Comments like `# Step 1:`, `# Step 2:` within the function body
- The function name requires "and" to describe what it does

---

## 4. Error Handling

### Handle Explicitly at Every Level

Never silently swallow errors. Every error should be:
- **Caught and handled** with a specific recovery action, OR
- **Caught, logged, and re-raised** for the caller to handle, OR
- **Allowed to propagate** naturally to a higher-level handler

### Patterns

```python
# WRONG: silently swallows all errors
def get_data(id):
    try:
        return service.fetch(id)
    except Exception:
        return None

# CORRECT: handles specific errors, propagates unexpected ones
def get_data(id: str) -> Data:
    try:
        return service.fetch(id)
    except NotFoundError:
        logger.info("data_not_found", id=id)
        raise
    except ConnectionError as e:
        logger.error("service_unavailable", id=id, error=str(e))
        raise ServiceUnavailableError(f"Cannot reach data service: {e}") from e
```

```typescript
// WRONG: empty catch block
try {
  await fetchData(id);
} catch (error) {
  // do nothing
}

// CORRECT: handle and provide context
try {
  await fetchData(id);
} catch (error) {
  if (error instanceof NotFoundError) {
    logger.info("data_not_found", { id });
    return null;
  }
  logger.error("fetch_failed", { id, error: String(error) });
  throw new ServiceError(`Failed to fetch data: ${error}`);
}
```

### Error Messages

- **User-facing:** clear, actionable, no technical details
- **Server-side:** detailed context for debugging (IDs, parameters, stack traces)
- **Never expose:** internal paths, database schema, stack traces, or credentials

---

## 5. Input Validation

### Validate at System Boundaries

System boundaries include:
- API endpoint handlers (request body, query parameters, path parameters)
- CLI argument parsing
- File content parsing
- Environment variable loading
- User form input
- External API response processing

### Principles

- **Fail fast** with clear error messages
- **Use schema-based validation** where available (Zod, Pydantic, JSON Schema)
- **Never trust external data** -- validate structure, types, ranges, and formats
- **Validate once at the boundary**, then pass typed data inward

```python
# Boundary: validate at the API endpoint
from pydantic import BaseModel, Field

class CreateUserRequest(BaseModel):
    email: str = Field(..., pattern=r"^[\w.+-]+@[\w-]+\.[\w.]+$")
    name: str = Field(..., min_length=1, max_length=200)
    age: int = Field(..., ge=0, le=150)

# Interior: function receives validated, typed data
def create_user(request: CreateUserRequest) -> User:
    # No need to re-validate here -- the boundary did it
    return User(email=request.email, name=request.name, age=request.age)
```

```typescript
// Boundary: validate at the API route
import { z } from "zod";

const CreateUserSchema = z.object({
  email: z.string().email(),
  name: z.string().min(1).max(200),
  age: z.number().int().min(0).max(150),
});

export async function POST(request: Request) {
  const body = await request.json();
  const validated = CreateUserSchema.parse(body);
  // validated is fully typed from here on
  return createUser(validated);
}
```

---

## 6. Naming Conventions

### Variables: Descriptive, Not Abbreviated

```
BAD:  d, tmp, val, x, res, cb, fn, cfg
GOOD: duration, temporaryFile, userCount, response, callback, formatter, config
```

### Functions: Verb-Noun Pattern

```
BAD:  data(), user(), process()
GOOD: fetchData(), createUser(), processOrder()
```

### Booleans: Question Form

```
BAD:  active, valid, loading
GOOD: isActive, isValid, isLoading, hasPermission, canEdit, shouldRetry
```

### Constants: SCREAMING_SNAKE_CASE

```
BAD:  maxRetries = 3, defaultTimeout = 5000
GOOD: MAX_RETRIES = 3, DEFAULT_TIMEOUT_MS = 5000
```

### Classes/Types: PascalCase, Noun

```
BAD:  userData, createUser, userHelper
GOOD: User, UserService, UserRepository
```

---

## 7. No Deep Nesting

### Maximum 4 Levels of Indentation

Deep nesting makes code hard to read and reason about.

```python
# BAD: 5+ levels of nesting
def process(users, filters, options):
    if users:
        for user in users:
            if user.active:
                for filter in filters:
                    if filter.matches(user):
                        if options.get("verbose"):
                            log(user)
                        results.append(user)

# GOOD: early returns and extraction
def process(users, filters, options):
    if not users:
        return []

    active_users = [u for u in users if u.active]
    matched = [u for u in active_users if any(f.matches(u) for f in filters)]

    if options.get("verbose"):
        for user in matched:
            log(user)

    return matched
```

### Techniques to Reduce Nesting

1. **Early returns / guard clauses** -- handle error cases first, then the happy path
2. **Extract helper functions** -- move nested logic into named functions
3. **Use comprehensions / functional style** -- filter, map, reduce instead of nested loops
4. **Invert conditions** -- `if not valid: return error` instead of `if valid: ... (100 lines)`

---

## Code Quality Checklist

Before marking work complete:

- [ ] Code is readable and well-named
- [ ] Functions are small (under 50 lines)
- [ ] Files are focused (under 800 lines)
- [ ] No deep nesting (max 4 levels)
- [ ] Proper error handling at every level
- [ ] No hardcoded values (use constants or config)
- [ ] No mutation (immutable patterns used)
- [ ] Input validated at system boundaries
- [ ] No unused imports, dead code, or debug statements
- [ ] Self-documenting (comments explain WHY, not WHAT)

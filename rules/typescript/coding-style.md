---
paths:
  - "**/*.ts"
  - "**/*.tsx"
  - "**/*.js"
  - "**/*.jsx"
---
# TypeScript/JavaScript Coding Style

> This file extends [common/coding-style.md](../common/coding-style.md) with TypeScript/JavaScript-specific content.

## Types and Interfaces

### Public APIs

- Add parameter and return types to exported functions, shared utilities, and public class methods
- Let TypeScript infer obvious local variable types
- Extract repeated inline object shapes into named types or interfaces

```typescript
// WRONG: Exported function without explicit types
export function formatUser(user) {
  return `${user.firstName} ${user.lastName}`
}

// CORRECT: Explicit types on public APIs
interface User {
  firstName: string
  lastName: string
}

export function formatUser(user: User): string {
  return `${user.firstName} ${user.lastName}`
}
```

### Interfaces vs. Type Aliases

- Use `interface` for object shapes that may be extended or implemented
- Use `type` for unions, intersections, tuples, mapped types, and utility types
- Prefer string literal unions over `enum` unless interop requires it

```typescript
interface User {
  id: string
  email: string
}

type UserRole = 'admin' | 'member'
type UserWithRole = User & { role: UserRole }
```

### Avoid `any`

- Avoid `any` in application code
- Use `unknown` for external or untrusted input, then narrow safely
- Use generics when a value's type depends on the caller

```typescript
// WRONG
function getErrorMessage(error: any) {
  return error.message
}

// CORRECT
function getErrorMessage(error: unknown): string {
  if (error instanceof Error) return error.message
  return 'Unexpected error'
}
```

## Immutability

Use spread operator and `Readonly<T>` for immutable updates:

```typescript
// WRONG: Mutation
function updateUser(user: User, name: string): User {
  user.name = name
  return user
}

// CORRECT: Immutable
function updateUser(user: Readonly<User>, name: string): User {
  return { ...user, name }
}
```

## Input Validation

Use Zod for schema-based validation:

```typescript
import { z } from 'zod'

const userSchema = z.object({
  email: z.string().email(),
  age: z.number().int().min(0).max(150),
})

type UserInput = z.infer<typeof userSchema>
```

## Error Handling

Use async/await with try-catch and narrow unknown errors safely:

```typescript
async function loadUser(userId: string): Promise<User> {
  try {
    return await fetchUser(userId)
  } catch (error: unknown) {
    logger.error('load_user_failed', error)
    throw new Error(getErrorMessage(error))
  }
}
```

## Console.log

- No `console.log` statements in production code
- Use proper logging libraries instead

# New Endpoint Workflow

Adding a new API endpoint that spans backend and frontend.

## Backend Side

### 1. Entity (if new data model)
- [ ] Create entity/model in your models directory
- [ ] Use your ORM's declarative model pattern
- [ ] Create a database migration (see `vault/workflows/database-migration.md`)

### 2. Repository
- [ ] Create repository with standard operations: `findAll`, `findById`, `create`, `update`, `delete`
- [ ] Use parameterized queries (never string interpolation)
- [ ] Return domain objects, not raw DB rows

### 3. Service
- [ ] Create service layer for business logic
- [ ] Business logic lives here, not in the controller
- [ ] Handle errors explicitly with specific exception types
- [ ] Return typed domain objects

### 4. Controller / Route Handler
- [ ] Create route handler with proper HTTP methods
- [ ] Input validation using schema validation (Pydantic, Zod, etc.)
- [ ] Authentication and authorization checks
- [ ] Register the route in your router/app

### 5. Tests
- [ ] Unit tests for service logic
- [ ] Integration tests for the HTTP layer
- [ ] Contract test: verify endpoint URL, method, request/response shape

```bash
# Run tests
pytest tests/path/to/test.py -x -v          # Python
npm test -- path/to/test.ts                  # TypeScript
```

## Frontend Side

### 6. API Client
- [ ] Add method to your API client module
- [ ] Use proper TypeScript types for request/response
- [ ] Handle error responses

### 7. Data Fetching Hook
- [ ] Create a hook using your data fetching library (React Query, SWR, etc.)
- [ ] Define cache key, stale time, error handling
- [ ] For mutations: handle optimistic updates if needed

### 8. UI Component
- [ ] Build or update the relevant page/component
- [ ] Handle all states: loading, error, empty, success
- [ ] Follow existing component patterns

### 9. Route (if proxying)
- [ ] Add route handler for API proxying if needed
- [ ] Include auth token forwarding

## Verification

- [ ] API responds correctly (test with curl or automated tests)
- [ ] Error responses are meaningful (not 500 with stack trace)
- [ ] Auth works (unauthenticated requests are rejected)
- [ ] Contract tests pass
- [ ] Health endpoint still returns 200

#workflow #endpoint

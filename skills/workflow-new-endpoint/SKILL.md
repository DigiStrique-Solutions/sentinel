---
name: sentinel-workflow-new-endpoint
description: Full-stack new-endpoint workflow — entity, repository, service, controller, tests, API client, data hook, UI component, proxy route. Use whenever the user says "add an endpoint", "new API route", "expose this over HTTP", "new REST endpoint", "new GraphQL query", "wire this up to the frontend", or otherwise asks to add an API surface spanning backend and frontend — even if they don't explicitly say "workflow". Walks the layered backend path (entity -> repo -> service -> controller -> tests) then the frontend path (client -> hook -> component -> proxy) and finishes with verification. Nine steps plus a verification phase.
workflow: true
workflow-steps: 9
allowed-tools: Read Grep Glob Bash Edit Write MultiEdit TodoWrite
origin: sentinel
---

# New Endpoint Workflow

Adding a new API endpoint that spans backend and frontend.

This is a Sentinel workflow skill. When it activates, the `sentinel-workflow-runner` protocol drives execution — creates a run directory, checkpoints progress after each step, and supports resumption across sessions. You do not need to invoke the runner explicitly; it activates alongside this skill.

## Protocol summary

At the top of the workflow, create a new run:

```bash
RUN_ID=$(bash "${CLAUDE_PLUGIN_ROOT}/scripts/workflow-state.sh" start new-endpoint)
```

Before each numbered step, call `step-start`. After each step completes, call `step-complete` (with an artifact path if you produced one). After the final step, call `finish <run-id> completed`. On failure, call `step-fail` and follow the failure-handling rules in each section below.

Full protocol details: see `sentinel-workflow-runner` skill.

---

## Backend Side

## 1. Entity (if new data model)

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/workflow-state.sh" step-start "$RUN_ID" 1 "Entity"
```

- [ ] Create entity/model in your models directory
- [ ] Use your ORM's declarative model pattern
- [ ] Create a database migration (see `sentinel-workflow-database-migration`)

**Write an artifact**: `vault/workflows/runs/$RUN_ID/artifacts/step-1-entity.md` with the entity file path, fields, and any migration created. If no new data model is needed, note "not applicable" and why.

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/workflow-state.sh" step-complete "$RUN_ID" 1 "artifacts/step-1-entity.md"
```

## 2. Repository

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/workflow-state.sh" step-start "$RUN_ID" 2 "Repository"
```

- [ ] Create repository with standard operations: `findAll`, `findById`, `create`, `update`, `delete`
- [ ] Use parameterized queries (never string interpolation)
- [ ] Return domain objects, not raw DB rows

**Write an artifact**: `artifacts/step-2-repository.md` with the repository file path and the operations defined.

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/workflow-state.sh" step-complete "$RUN_ID" 2 "artifacts/step-2-repository.md"
```

## 3. Service

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/workflow-state.sh" step-start "$RUN_ID" 3 "Service"
```

- [ ] Create service layer for business logic
- [ ] Business logic lives here, not in the controller
- [ ] Handle errors explicitly with specific exception types
- [ ] Return typed domain objects

**Write an artifact**: `artifacts/step-3-service.md` with the service file path, the business rules implemented, and the exception types used.

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/workflow-state.sh" step-complete "$RUN_ID" 3 "artifacts/step-3-service.md"
```

## 4. Controller / Route Handler

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/workflow-state.sh" step-start "$RUN_ID" 4 "Controller"
```

- [ ] Create route handler with proper HTTP methods
- [ ] Input validation using schema validation (Pydantic, Zod, etc.)
- [ ] Authentication and authorization checks
- [ ] Register the route in your router/app

**Write an artifact**: `artifacts/step-4-controller.md` with the HTTP method, URL, validation schema, and auth checks.

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/workflow-state.sh" step-complete "$RUN_ID" 4 "artifacts/step-4-controller.md"
```

## 5. Tests

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/workflow-state.sh" step-start "$RUN_ID" 5 "Tests"
```

- [ ] Unit tests for service logic
- [ ] Integration tests for the HTTP layer
- [ ] Contract test: verify endpoint URL, method, request/response shape

```bash
# Run tests
pytest tests/path/to/test.py -x -v          # Python
npm test -- path/to/test.ts                  # TypeScript
```

**Write an artifact**: `artifacts/step-5-tests.md` with test file paths and the test run output.

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/workflow-state.sh" step-complete "$RUN_ID" 5 "artifacts/step-5-tests.md"
```

## Frontend Side

## 6. API Client

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/workflow-state.sh" step-start "$RUN_ID" 6 "API Client"
```

- [ ] Add method to your API client module
- [ ] Use proper TypeScript types for request/response
- [ ] Handle error responses

**Write an artifact**: `artifacts/step-6-client.md` with the client file path and the new method signature.

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/workflow-state.sh" step-complete "$RUN_ID" 6 "artifacts/step-6-client.md"
```

## 7. Data Fetching Hook

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/workflow-state.sh" step-start "$RUN_ID" 7 "Data Fetching Hook"
```

- [ ] Create a hook using your data fetching library (React Query, SWR, etc.)
- [ ] Define cache key, stale time, error handling
- [ ] For mutations: handle optimistic updates if needed

**Write an artifact**: `artifacts/step-7-hook.md` with the hook file path, cache key, and stale-time settings.

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/workflow-state.sh" step-complete "$RUN_ID" 7 "artifacts/step-7-hook.md"
```

## 8. UI Component

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/workflow-state.sh" step-start "$RUN_ID" 8 "UI Component"
```

- [ ] Build or update the relevant page/component
- [ ] Handle all states: loading, error, empty, success
- [ ] Follow existing component patterns

**Write an artifact**: `artifacts/step-8-component.md` with the component file path and the states handled.

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/workflow-state.sh" step-complete "$RUN_ID" 8 "artifacts/step-8-component.md"
```

## 9. Route (if proxying)

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/workflow-state.sh" step-start "$RUN_ID" 9 "Proxy Route"
```

- [ ] Add route handler for API proxying if needed
- [ ] Include auth token forwarding

**Write an artifact**: `artifacts/step-9-proxy.md` with the proxy route path and auth forwarding details. If no proxy is needed, note "not applicable".

Also run the verification checklist below before marking complete:

## Verification

- [ ] API responds correctly (test with curl or automated tests)
- [ ] Error responses are meaningful (not 500 with stack trace)
- [ ] Auth works (unauthenticated requests are rejected)
- [ ] Contract tests pass
- [ ] Health endpoint still returns 200

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/workflow-state.sh" step-complete "$RUN_ID" 9 "artifacts/step-9-proxy.md"
bash "${CLAUDE_PLUGIN_ROOT}/scripts/workflow-state.sh" finish "$RUN_ID" completed
```

#workflow #endpoint

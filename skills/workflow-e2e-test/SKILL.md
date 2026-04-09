---
name: sentinel-workflow-e2e-test
description: End-to-end test authoring workflow — write, auth, wait strategy, run, organize, review artifacts. Use whenever the user says "write an e2e test", "playwright test", "cypress test", "end-to-end", "browser test", "UI test", "flaky test", or mentions Playwright/Cypress/Selenium — even if they don't explicitly say "workflow". Enforces the Page Object Model pattern, bans `networkidle` waits in favor of explicit element/response waits, and requires deterministic, independent tests. Six steps — write, auth, wait strategy, run, organize, artifacts.
workflow: true
workflow-steps: 6
allowed-tools: Read Grep Glob Bash Edit Write MultiEdit TodoWrite
origin: sentinel
paths: "**/e2e/** **/*.e2e.* **/playwright/** **/cypress/** tests/e2e/**"
---

# E2E Test Workflow

Writing and running end-to-end tests. Framework-agnostic steps for any E2E tool (Playwright, Cypress, Selenium, etc.).

This is a Sentinel workflow skill. When it activates, the `sentinel-workflow-runner` protocol drives execution — creates a run directory, checkpoints progress after each step, and supports resumption across sessions. You do not need to invoke the runner explicitly; it activates alongside this skill.

## Protocol summary

At the top of the workflow, create a new run:

```bash
RUN_ID=$(bash "${CLAUDE_PLUGIN_ROOT}/scripts/workflow-state.sh" start e2e-test)
```

Before each numbered step, call `step-start`. After each step completes, call `step-complete` (with an artifact path if you produced one). After the final step, call `finish <run-id> completed`. On failure, call `step-fail` and follow the failure-handling rules in each section below.

Full protocol details: see `sentinel-workflow-runner` skill.

---

## 1. Write the Test

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/workflow-state.sh" step-start "$RUN_ID" 1 "Write the Test"
```

- [ ] Use Page Object Model (POM) pattern for maintainability
- [ ] Never use `networkidle` -- use `domcontentloaded` + explicit element waits
- [ ] Use realistic test data and user flows
- [ ] Include assertions for both success and failure states

```typescript
// Example using Page Object Model
test('should create item successfully', async ({ page }) => {
  const itemPage = new ItemPage(page);
  await itemPage.goto();
  await itemPage.fillName('Test Item');
  await itemPage.selectCategory('Electronics');
  await itemPage.submit();

  await expect(itemPage.successMessage).toBeVisible();
  await expect(itemPage.itemName).toHaveText('Test Item');
});
```

**Write an artifact**: `vault/workflows/runs/$RUN_ID/artifacts/step-1-test.md` recording the test file path, the flow it covers, and which page objects were used or created.

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/workflow-state.sh" step-complete "$RUN_ID" 1 "artifacts/step-1-test.md"
```

## 2. Handle Authentication

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/workflow-state.sh" step-start "$RUN_ID" 2 "Handle Authentication"
```

- [ ] Use stored auth state to avoid logging in for every test
- [ ] Set up auth state in a global setup file
- [ ] Never hardcode credentials in test files -- use environment variables

**Write an artifact**: `artifacts/step-2-auth.md` describing the auth-state approach and where credentials come from.

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/workflow-state.sh" step-complete "$RUN_ID" 2 "artifacts/step-2-auth.md"
```

## 3. Wait Strategy

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/workflow-state.sh" step-start "$RUN_ID" 3 "Wait Strategy"
```

**Never use `networkidle`** -- applications with SSE, WebSockets, or background requests never become idle.

Instead:
- Wait for specific elements: `await expect(locator).toBeVisible()`
- Wait for network responses: `await page.waitForResponse(url)`
- Wait for DOM state: `await page.waitForSelector('.loaded')`
- Set reasonable timeouts (30s for standard flows, longer for complex operations)

**Write an artifact**: `artifacts/step-3-waits.md` listing every wait in the test and why it's appropriate.

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/workflow-state.sh" step-complete "$RUN_ID" 3 "artifacts/step-3-waits.md"
```

## 4. Run Tests

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/workflow-state.sh" step-start "$RUN_ID" 4 "Run Tests"
```

```bash
# Playwright
npx playwright test
npx playwright test --grep "item creation"
npx playwright test --debug

# Cypress
npx cypress run
npx cypress open

# Generic
npm run e2e
```

**Write an artifact**: `artifacts/step-4-run.md` with the test run output and pass/fail summary.

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/workflow-state.sh" step-complete "$RUN_ID" 4 "artifacts/step-4-run.md"
```

## 5. Test Organization

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/workflow-state.sh" step-start "$RUN_ID" 5 "Test Organization"
```

- [ ] Group tests by feature or user flow
- [ ] Keep test files focused -- one flow per file
- [ ] Share page objects and utilities across tests
- [ ] Use test fixtures for common setup

**Write an artifact**: `artifacts/step-5-organization.md` describing where the new test lives in the test tree and any shared helpers touched.

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/workflow-state.sh" step-complete "$RUN_ID" 5 "artifacts/step-5-organization.md"
```

## 6. Artifacts

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/workflow-state.sh" step-start "$RUN_ID" 6 "Artifacts"
```

Tests should generate artifacts on failure:
- Screenshots
- Videos
- Trace files
- Console logs

Review these when tests fail -- they're often more informative than the error message.

**Write an artifact**: `artifacts/step-6-artifacts.md` listing where failure artifacts are stored and any review notes from looking at them.

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/workflow-state.sh" step-complete "$RUN_ID" 6 "artifacts/step-6-artifacts.md"
bash "${CLAUDE_PLUGIN_ROOT}/scripts/workflow-state.sh" finish "$RUN_ID" completed
```

## Key Rules

- **No `networkidle`.** Use explicit waits for specific elements or responses.
- **Page Object Model.** Encapsulate selectors and actions in page objects.
- **Realistic data.** Use data that resembles production, not "test123".
- **Mock external APIs** when testing UI flows -- don't depend on third-party services being available.
- **Deterministic tests.** Tests must produce the same result every run. No race conditions, no flaky assertions.
- **Independent tests.** Each test should set up its own state. No test should depend on another test running first.

#workflow #e2e #testing

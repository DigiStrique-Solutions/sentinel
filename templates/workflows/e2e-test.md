# E2E Test Workflow

Writing and running end-to-end tests. Framework-agnostic steps for any E2E tool (Playwright, Cypress, Selenium, etc.).

## 1. Write the Test

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

## 2. Handle Authentication

- [ ] Use stored auth state to avoid logging in for every test
- [ ] Set up auth state in a global setup file
- [ ] Never hardcode credentials in test files -- use environment variables

## 3. Wait Strategy

**Never use `networkidle`** -- applications with SSE, WebSockets, or background requests never become idle.

Instead:
- Wait for specific elements: `await expect(locator).toBeVisible()`
- Wait for network responses: `await page.waitForResponse(url)`
- Wait for DOM state: `await page.waitForSelector('.loaded')`
- Set reasonable timeouts (30s for standard flows, longer for complex operations)

## 4. Run Tests

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

## 5. Test Organization

- [ ] Group tests by feature or user flow
- [ ] Keep test files focused -- one flow per file
- [ ] Share page objects and utilities across tests
- [ ] Use test fixtures for common setup

## 6. Artifacts

Tests should generate artifacts on failure:
- Screenshots
- Videos
- Trace files
- Console logs

Review these when tests fail -- they're often more informative than the error message.

## Key Rules

- **No `networkidle`.** Use explicit waits for specific elements or responses.
- **Page Object Model.** Encapsulate selectors and actions in page objects.
- **Realistic data.** Use data that resembles production, not "test123".
- **Mock external APIs** when testing UI flows -- don't depend on third-party services being available.
- **Deterministic tests.** Tests must produce the same result every run. No race conditions, no flaky assertions.
- **Independent tests.** Each test should set up its own state. No test should depend on another test running first.

#workflow #e2e #testing

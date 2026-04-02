---
paths:
  - "**/*.ts"
  - "**/*.tsx"
  - "**/*.js"
  - "**/*.jsx"
---
# TypeScript/JavaScript Testing

> This file extends [common/testing.md](../common/testing.md) with TypeScript/JavaScript-specific content.

## Unit Testing Framework

Use **Vitest** or **Jest** for unit and integration tests.

```typescript
describe('calculateTotal', () => {
  it('should sum all item prices', () => {
    const items = [{ price: 10 }, { price: 20 }, { price: 30 }]
    expect(calculateTotal(items)).toBe(60)
  })

  it('should return 0 for empty array', () => {
    expect(calculateTotal([])).toBe(0)
  })

  it('should throw for negative prices', () => {
    expect(() => calculateTotal([{ price: -1 }])).toThrow('negative price')
  })
})
```

## Component Testing

Use **React Testing Library** for component tests:

```typescript
import { render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'

describe('UserCard', () => {
  it('should display user name and handle click', async () => {
    const onSelect = vi.fn()
    render(<UserCard user={{ id: '1', name: 'Alice' }} onSelect={onSelect} />)

    expect(screen.getByText('Alice')).toBeInTheDocument()
    await userEvent.click(screen.getByRole('button'))
    expect(onSelect).toHaveBeenCalledWith('1')
  })
})
```

## Hook Testing

```typescript
import { renderHook, act } from '@testing-library/react'

describe('useCounter', () => {
  it('should increment count', () => {
    const { result } = renderHook(() => useCounter())

    act(() => result.current.increment())

    expect(result.current.count).toBe(1)
  })
})
```

## E2E Testing

Use **Playwright** for end-to-end tests on critical user flows:

```typescript
test('should complete checkout flow', async ({ page }) => {
  await page.goto('/cart')
  await page.getByRole('button', { name: 'Checkout' }).click()
  await expect(page.getByText('Order confirmed')).toBeVisible()
})
```

## Coverage

```bash
# Vitest
vitest run --coverage

# Jest
jest --coverage
```

## Reference

See skill: `e2e-testing` for Playwright patterns and Page Object Model.

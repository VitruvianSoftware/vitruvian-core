---
name: Quality Assurance Engineer
description:
  Expert guidance for testing Vitruvian Tabs using Jest, Playwright, and browser-based verification
---

# Quality Assurance Engineer

You are an expert QA engineer specializing in testing the Vitruvian Tabs browser extension and API.

## Testing Philosophy

Vitruvian Tabs follows the **Test Pyramid** approach:

```
        /\
       /  \
      / E2E \       (10% - Critical user flows)
     /______\
    /        \
   /Integration\   (30% - API endpoints, DB)
  /____________\
 /              \
/   Unit Tests   \  (60% - Business logic)
/________________\
```

## Testing Commands

Run all tests through Bazel (never `vitruvian-tabs dev ...` or `npm test --workspace=...`):

```bash
# Unit + hermetic Rust integration suites
bazel test //apps/suites/vitruvian-tabs/...

# Component-specific unit tests
bazel test //apps/suites/vitruvian-tabs/extension:unit_tests
bazel test //apps/suites/vitruvian-tabs/api:vitruvian_tabs_api_tools_test //apps/suites/vitruvian-tabs/api:integration_tests
bazel test //apps/suites/vitruvian-tabs/cli:unit_tests

# Playwright E2E (boots Postgres, Redis, migrations, and API via rules_itest)
bazel test --config=e2e //apps/suites/vitruvian-tabs/...
```

## Unit Test Patterns

### Jest Setup

```typescript
describe('ServiceName', () => {
  describe('methodName', () => {
    it('should do something specific', async () => {
      // Arrange
      const input = 'test input';
      const expected = 'expected output';

      // Act
      const result = await functionUnderTest(input);

      // Assert
      expect(result).toBe(expected);
    });
  });
});
```

### Chrome API Mocking

```typescript
// setupTests.ts - Mock chrome global
global.chrome = {
  tabs: {
    query: jest.fn(),
    create: jest.fn(),
    remove: jest.fn(),
    move: jest.fn(),
    group: jest.fn(),
    ungroup: jest.fn(),
  },
  storage: {
    local: {
      get: jest.fn(),
      set: jest.fn(),
    },
  },
  tabGroups: {
    query: jest.fn(),
    update: jest.fn(),
  },
} as unknown as typeof chrome;
```

### API Route Testing (Rust)

API integration tests run in-process against `AppContext::new_test()` and `handle_request()` (`api/rs/src/tests_integration.rs`):

```rust
let ctx = AppContext::new_test();
let token = ctx.sign_user_token("user-1", "user@example.com", "free");
let req = HttpRequest::new("POST", "/api/v1/workspaces")
    .with_auth(&token)
    .with_json(&json!({ "name": "Work" }));
let resp = handle_request(&ctx, &req);
assert_eq!(resp.status, 201);
```

## E2E Test Patterns (Playwright)

```typescript
// extension/tests/sync-journeys.spec.ts
test('create and restore workspace', async ({ page }) => {
  await page.goto('chrome-extension://popup.html');

  // Create workspace
  await page.click('[data-testid="new-workspace"]');
  await page.fill('[data-testid="workspace-name"]', 'Test');
  await page.click('[data-testid="save-workspace"]');

  // Verify
  await expect(page.locator('[data-testid="workspace-item"]')).toHaveText('Test');
});
```

## Browser Subagent Verification

From AGENTS.md - Manual verification for UI/Sync logic:

1. Load `chrome-extension://<id>/dashboard.html` in browser subagent
2. Perform action (create space, rename, etc.)
3. Reload page
4. Verify change persists

**Key verification points**:

- Persistence after reload (API validation)
- Console errors (capture_browser_console_logs)
- Strict mode selectors

## Verified User Journeys

Critical paths that MUST work:

1. **Create Space**: Should appear immediately
2. **Rename Space**: Must persist after reload
3. **Create Section**: Should appear in sidebar
4. **Rename Section**: Uses `prompt()` dialog
5. **Delete/Archive**: Should remove from view

## Common Test Hazards

1. **Flaky Tests**: Use `waitFor` for async conditions
2. **Shared State**: Clean up in `afterEach`
3. **Mock Timing**: Reset mocks between tests with `jest.clearAllMocks()`
4. **Force-Remote Window**: Mock `vitruvian_tabs_force_remote_until` for restore tests

## Key Files to Reference

- [Testing Guide](../../../docs/guides/testing.md)
- [AGENTS.md](../../../AGENTS.md)
- [Verified Journeys](../../../docs/product/verified-journeys.md)
- [Commit Readiness Workflow](../../workflows/commit-readiness.md)

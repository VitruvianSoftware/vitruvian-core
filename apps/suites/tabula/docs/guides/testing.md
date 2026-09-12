# Testing Guide

This document outlines Tabula's testing philosophy, strategies, and best practices.

## Table of Contents

- [Testing Philosophy](#testing-philosophy)
- [Test Types](#test-types)
- [Coverage Requirements](#coverage-requirements)
- [Writing Tests](#writing-tests)
- [Running Tests](#running-tests)
- [Mocking Strategies](#mocking-strategies)
- [Test Organization](#test-organization)
- [Best Practices](#best-practices)
- [Common Patterns](#common-patterns)
- [Troubleshooting](#troubleshooting)

## Testing Philosophy

Our testing strategy follows the **Test Pyramid** approach:

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

### Key Principles

1. **Test Behavior, Not Implementation:** Focus on what the code does, not how it does it
2. **Fast Feedback:** Unit tests should run in milliseconds
3. **Isolation:** Each test should be independent
4. **Readability:** Tests are documentation
5. **Maintainability:** Keep tests DRY but clear

## Test Types

### Unit Tests (60%)

**Purpose:** Test individual functions and methods in isolation

**Characteristics:**

- Fast execution (< 100ms per test)
- No external dependencies
- Test single responsibility
- Mock external services

**When to write:**

- Service layer functions
- Utility functions
- Data transformations
- Validation logic
- Pure functions

**Example:**

```typescript
// api/tests/unit/auth.service.test.ts
describe('AuthService', () => {
  describe('hashPassword', () => {
    it('should hash a password successfully', async () => {
      const password = 'TestPassword123!';
      const hash = await hashPassword(password);

      expect(hash).toBeDefined();
      expect(hash).not.toBe(password);
      expect(hash.length).toBeGreaterThan(50);
    });
  });
});
```

### Integration Tests (30%)

**Purpose:** Test interaction between components

**Characteristics:**

- Test API endpoints
- Use test database
- Verify request/response
- Test authentication flows

**When to write:**

- API routes
- Database operations
- External API integrations
- Authentication/authorization

**Example:**

```typescript
// api/tests/integration/workspace.test.ts
describe('POST /api/v1/workspaces', () => {
  it('should create a new workspace', async () => {
    const response = await request(app)
      .post('/api/v1/workspaces')
      .set('Authorization', `Bearer ${validToken}`)
      .send({ name: 'Work', color: '#0066CC' });

    expect(response.status).toBe(201);
    expect(response.body).toMatchObject({
      id: expect.any(String),
      name: 'Work',
      color: '#0066CC',
    });
  });
});
```

### E2E Tests (10%)

**Purpose:** Test complete user workflows

**Characteristics:**

- Real browser testing
- Test critical paths
- Slower execution
- Test user interactions

**When to write:**

- Critical user journeys
- Multi-step workflows
- Cross-component features
- Real browser behavior

**Example:**

```typescript
// extension/tests/e2e/workspace.spec.ts
test('create and use workspace', async ({ page }) => {
  await page.goto('chrome-extension://popup.html');

  // Create workspace
  await page.click('[data-testid="new-workspace"]');
  await page.fill('[data-testid="workspace-name"]', 'Work');
  await page.click('[data-testid="save-workspace"]');

  // Verify created
  await expect(page.locator('[data-testid="workspace-item"]')).toHaveText('Work');
});
```

## Coverage Requirements

### Minimum Thresholds (Enforced)

```javascript
coverageThresholds: {
  global: {
    branches: 80,
    functions: 80,
    lines: 80,
    statements: 80,
  },
}
```

**New: Detailed Reporting** The CI pipeline and `tabcli dev coverage --detailed` now provide
per-file coverage breakdowns, sorted by coverage level (worst first), making it easy to identify
files that need improvement.

````

### What to Cover

**Must have 100% coverage:**

- Authentication logic
- Authorization checks
- Payment processing (future)
- Data validation

**Must have 80%+ coverage:**

- API routes
- Service layer
- Utility functions

**Can have lower coverage:**

- Configuration files
- Type definitions
- Generated code

## Writing Tests

### Test Structure (AAA Pattern)

```typescript
describe('Feature or Component', () => {
  it('should do something specific', () => {
    // Arrange: Set up test data and conditions
    const input = 'test input';
    const expected = 'expected output';

    // Act: Execute the code being tested
    const result = functionUnderTest(input);

    // Assert: Verify the result
    expect(result).toBe(expected);
  });
});
````

### Naming Conventions

**Test Files:**

- Unit tests: `*.test.ts`
- Integration tests: `*.test.ts`
- E2E tests: `*.spec.ts` or `*.e2e.ts`

**Describe Blocks:**

```typescript
describe('ServiceName or ComponentName', () => {
  describe('methodName or feature', () => {
    // tests here
  });
});
```

**Test Cases:**

```typescript
// Good
it('should return 401 when token is invalid', () => {});
it('should create workspace with valid data', () => {});

// Bad
it('works', () => {});
it('test1', () => {});
```

### Test Data

**Use Fixtures:**

```typescript
// api/tests/fixtures/index.ts
export const mockUser = {
  id: '123e4567-e89b-12d3-a456-426614174000',
  email: 'test@example.com',
  name: 'Test User',
};
```

**Use Builders for Complex Objects:**

```typescript
class UserBuilder {
  private user = { ...defaultUser };

  withEmail(email: string) {
    this.user.email = email;
    return this;
  }

  build() {
    return this.user;
  }
}

const user = new UserBuilder().withEmail('custom@example.com').build();
```

## Running Tests

### Basic Commands

```bash
# Run all tests
npm run dev --workspace=cli -- dev test

# Run tests for specific workspace
npm test --workspace=api
npm test --workspace=extension

# Run tests in watch mode
npm run test:watch --workspace=api

# Run with coverage
# Run with coverage (summary only)
npm run test:coverage

# Run with detailed per-file coverage breakdown
tabcli dev coverage --detailed

# Run specific test file
npm test --workspace=api -- tests/unit/auth.service.test.ts

# Run tests matching pattern
npm test --workspace=api -- --testNamePattern="should create"
```

### CI/CD Testing

Tests run automatically on:

- Every pull request
- Pushes to main branch
- Manual workflow dispatch

**CI Test Workflow:**

1. Install dependencies
2. Run linter (`npm run dev --workspace=cli -- dev lint`)
3. Run type checker
4. Run unit tests (parallel) (`npm run dev --workspace=cli -- dev test`)
5. Run integration tests (with test DB)
6. Run E2E tests (browser matrix)
7. Upload coverage to Codecov

## Mocking Strategies

### Database Mocking

**Option 1: Test Database (Preferred for Integration)**

```typescript
beforeAll(async () => {
  await prisma.$connect();
});

afterAll(async () => {
  await prisma.$disconnect();
});

beforeEach(async () => {
  await prisma.user.deleteMany();
});
```

**Option 2: Mock Prisma Client (Unit Tests)**

```typescript
jest.mock('@prisma/client', () => ({
  PrismaClient: jest.fn(() => ({
    user: {
      create: jest.fn(),
      findUnique: jest.fn(),
    },
  })),
}));
```

### External API Mocking

```typescript
// Mock fetch
global.fetch = jest.fn(() =>
  Promise.resolve({
    json: () => Promise.resolve({ data: 'mock data' }),
  })
) as jest.Mock;

// Or use nock for HTTP mocking
import nock from 'nock';

nock('https://api.example.com').get('/users').reply(200, { users: [] });
```

### Time Mocking

```typescript
// Mock Date
jest.useFakeTimers();
jest.setSystemTime(new Date('2025-01-01'));

// Advance time
jest.advanceTimersByTime(1000);

// Restore real timers
jest.useRealTimers();
```

## Test Organization

```
api/tests/
├── unit/
│   ├── services/
│   │   ├── auth.service.test.ts
│   │   └── workspace.service.test.ts
│   └── utils/
│       └── validation.test.ts
├── integration/
│   ├── auth.test.ts
│   └── workspace.test.ts
├── fixtures/
│   ├── index.ts
│   └── users.ts
├── helpers/
│   ├── testApp.ts          # Test server setup
│   └── database.ts          # DB helpers
└── setup.ts                 # Global setup
```

## Best Practices

### DO ✅

- **Write tests first** for new features (TDD when appropriate)
- **Test edge cases** and error conditions
- **Use descriptive names** that explain what is being tested
- **Keep tests simple** and focused on one thing
- **Use test fixtures** for consistent test data
- **Clean up** after tests (database, files, etc.)
- **Test both success and failure** paths
- **Mock external dependencies** in unit tests
- **Use type safety** in tests

### DON'T ❌

- **Don't test implementation details** (test behavior)
- **Don't write flaky tests** (tests that randomly fail)
- **Don't share state** between tests
- **Don't test third-party libraries**
- **Don't skip error cases**
- **Don't use magic numbers** (use named constants)
- **Don't write overly complex tests**
- **Don't duplicate production code** in tests

## Common Patterns

### Testing Async Code

```typescript
it('should handle async operations', async () => {
  const result = await asyncFunction();
  expect(result).toBe(expected);
});
```

### Testing Errors

```typescript
it('should throw error for invalid input', async () => {
  await expect(functionThatThrows()).rejects.toThrow('Expected error message');
});
```

### Testing with Setup/Teardown

```typescript
describe('UserService', () => {
  let service: UserService;

  beforeEach(() => {
    service = new UserService();
  });

  afterEach(() => {
    // Cleanup
  });

  it('should create user', async () => {
    // Test using service
  });
});
```

### Parameterized Tests

```typescript
describe.each([
  ['free', 10],
  ['pro', -1],
  ['team', -1],
])('workspace limits for %s tier', (tier, limit) => {
  it(`should enforce limit of ${limit}`, () => {
    const result = getWorkspaceLimit(tier);
    expect(result).toBe(limit);
  });
});
```

## Troubleshooting

### Tests Timing Out

```typescript
// Increase timeout for specific test
it('slow test', async () => {
  // test code
}, 30000); // 30 seconds

// Or in beforeAll
beforeAll(async () => {
  jest.setTimeout(30000);
});
```

### Database Connection Issues

```bash
# Ensure test database is running
docker-compose ps

# Check DATABASE_URL in tests/setup.ts
echo $DATABASE_URL
```

### Flaky Tests

**Common causes:**

- Race conditions
- Shared state between tests
- Timing dependencies
- External service calls

**Solutions:**

- Use `waitFor` for async conditions
- Clean up state in `afterEach`
- Mock external services
- Use test isolation

### Mock Not Working

```typescript
// Ensure mock is defined before import
jest.mock('./service');
import { service } from './service';

// Reset mocks between tests
afterEach(() => {
  jest.clearAllMocks();
});
```

## Test Metrics

### What We Measure

- **Coverage:** % of code covered by tests
- **Test Count:** Number of tests per module
- **Test Speed:** Time to run test suite
- **Flakiness:** % of tests that fail randomly

### Goals

- Coverage: >80% for all modules
- Unit test speed: <10 seconds total
- Integration test speed: <30 seconds total
- E2E test speed: <2 minutes total
- Flakiness: <1%

## Resources

- [Jest Documentation](https://jestjs.io/docs/getting-started)
- [Testing Library](https://testing-library.com/)
- [Playwright Docs](https://playwright.dev/)
- [Test Pyramid](https://martinfowler.com/articles/practical-test-pyramid.html)
- [Testing Best Practices](https://testingjavascript.com/)

---

**Remember:** Good tests are your safety net for refactoring and adding features!

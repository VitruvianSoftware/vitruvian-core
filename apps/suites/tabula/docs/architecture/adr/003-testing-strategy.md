# ADR-003: Testing Strategy

**Status:** Accepted  
**Date:** 2025-12-07  
**Deciders:** Tabula Core Team

## Context

Tabula needs a comprehensive testing strategy that:

- Ensures code quality and reliability
- Catches bugs early in development
- Supports continuous integration/deployment
- Provides confidence for refactoring
- Maintains high coverage (>80%)
- Tests at multiple levels (unit, integration, E2E)
- Works well with TypeScript
- Integrates with GitHub Actions CI

## Decision

We will implement a multi-layered testing strategy:

**Test Framework:** Jest

- Unit and integration tests
- TypeScript support via ts-jest
- Coverage reporting
- Mocking capabilities

**E2E Testing:** Playwright

- Browser extension testing
- Cross-browser support (Chrome, Edge)
- Screenshot and video capture
- Reliable test execution

**API Testing:** Supertest

- HTTP endpoint testing
- Integration with Jest
- Easy request/response testing

**Coverage Requirements:**

- Minimum 80% coverage across:
  - Branches
  - Functions
  - Lines
  - Statements
- Enforced via Jest configuration
- Reported to Codecov

## Consequences

### Positive

1. **Consistency:**
   - Jest used for both API and Extension
   - Single test syntax and patterns
   - Shared configuration and utilities

2. **Developer Experience:**
   - Fast test execution
   - Watch mode for development
   - Clear error messages
   - Snapshot testing support

3. **TypeScript Integration:**
   - Full TypeScript support
   - Type checking in tests
   - IntelliSense in test files

4. **Coverage Tracking:**
   - Automated coverage reports
   - Integration with Codecov
   - PR comments with coverage changes
   - Block merges below threshold

5. **E2E Reliability:**
   - Playwright more reliable than Selenium
   - Auto-waiting for elements
   - Built-in retry logic
   - Better debugging tools

6. **CI/CD Integration:**
   - Parallel test execution
   - Test result artifacts
   - Screenshots/videos on failure
   - Fast feedback loop

### Negative

1. **Test Execution Time:**
   - Full test suite takes time
   - Mitigated: Parallel execution, focused test runs

2. **E2E Flakiness:**
   - Browser tests can be flaky
   - Mitigated: Playwright's auto-retry, good test design

3. **Maintenance:**
   - Tests require ongoing maintenance
   - Mitigated: Good testing patterns, clear documentation

### Neutral

1. **Learning Curve:** Jest and Playwright are well-documented
2. **Tooling:** Industry-standard tools with good support

## Test Pyramid

```
        /\
       /  \
      / E2E \       (10% - Critical user flows)
     /______\
    /        \
   /Integration\   (30% - API endpoints, DB interactions)
  /____________\
 /              \
/   Unit Tests   \  (60% - Business logic, utilities)
/________________\
```

### Unit Tests (60%)

**What to test:**

- Business logic functions
- Utility functions
- Service layer methods
- Input validation
- Data transformations

**Example:**

```typescript
describe('AuthService', () => {
  it('should hash passwords correctly', async () => {
    const hash = await hashPassword('password');
    expect(hash).not.toBe('password');
  });
});
```

### Integration Tests (30%)

**What to test:**

- API endpoints
- Database operations
- External service integration
- Authentication flows
- Error handling

**Example:**

```typescript
describe('POST /api/v1/workspaces', () => {
  it('should create workspace', async () => {
    const response = await request(app)
      .post('/api/v1/workspaces')
      .set('Authorization', `Bearer ${token}`)
      .send({ name: 'Work' });
    expect(response.status).toBe(201);
  });
});
```

### E2E Tests (10%)

**What to test:**

- Critical user journeys
- Cross-component workflows
- Browser extension functionality
- Real browser interactions

**Example:**

```typescript
test('create and restore workspace', async ({ page }) => {
  await page.goto('chrome-extension://...');
  await page.click('[data-testid="new-workspace"]');
  // ... more steps
});
```

## Test Organization

```
api/tests/
├── unit/              # Unit tests for functions/services
├── integration/       # API endpoint integration tests
├── fixtures/          # Test data and mocks
├── helpers/           # Test utilities
└── setup.ts          # Global test setup

extension/tests/
├── unit/              # Component and utility tests
├── e2e/               # Playwright E2E tests
└── fixtures/          # Test data
```

## Coverage Thresholds

Enforced in Jest config:

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

## Naming Conventions

- Test files: `*.test.ts` or `*.spec.ts`
- E2E files: `*.e2e.ts` or `*.spec.ts`
- Describe blocks: Feature or component name
- Test cases: "should [expected behavior]"

## Mocking Strategy

1. **Database:** In-memory or test database
2. **External APIs:** Mock with Jest
3. **Time:** Mock with Jest fake timers
4. **File system:** Mock when needed

## CI Integration

**On Pull Request:**

- Run all unit tests
- Run all integration tests
- Run affected E2E tests
- Report coverage to Codecov
- Fail if coverage drops below threshold

**On Push to Main:**

- Run full test suite
- Deploy to staging
- Run smoke tests

## Alternatives Considered

### Alternative 1: Mocha + Chai

**Pros:**

- Flexible
- Modular design
- Good ecosystem

**Cons:**

- More configuration needed
- No built-in coverage
- Less TypeScript integration

**Why not chosen:** Jest provides better out-of-box experience.

### Alternative 2: Vitest

**Pros:**

- Very fast (Vite-based)
- Jest-compatible API
- Great TypeScript support

**Cons:**

- Relatively new
- Smaller ecosystem
- Less mature

**Why not chosen:** Jest is more mature and widely adopted.

### Alternative 3: Selenium for E2E

**Pros:**

- Mature
- Wide browser support
- Large ecosystem

**Cons:**

- Flaky tests
- Slower execution
- Complex setup

**Why not chosen:** Playwright is more reliable and modern.

### Alternative 4: Cypress

**Pros:**

- Great DX
- Time-travel debugging
- Good documentation

**Cons:**

- Browser extension testing limitations
- Separate test environment
- More complex for our use case

**Why not chosen:** Playwright better for extension testing.

## Implementation Plan

1. **Phase 1:** Setup Jest for unit tests
2. **Phase 2:** Add integration tests with Supertest
3. **Phase 3:** Configure Playwright for E2E
4. **Phase 4:** Integrate with CI/CD
5. **Phase 5:** Add Codecov integration

## References

- [Jest Documentation](https://jestjs.io/docs/getting-started)
- [Playwright Documentation](https://playwright.dev/)
- [Supertest Documentation](https://github.com/visionmedia/supertest)
- [Testing Best Practices](https://testingjavascript.com/)
- [Test Pyramid Pattern](https://martinfowler.com/articles/practical-test-pyramid.html)

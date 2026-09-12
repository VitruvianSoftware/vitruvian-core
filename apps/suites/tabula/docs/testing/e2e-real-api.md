# E2E Testing with Real API

This guide explains how to run extension E2E tests against a real API server.

## Prerequisites

- API server running (`tabcli dev start --api`)
- Database with migrations applied
- Node.js 18+

## Running E2E Tests with Real API

### Option A: Use tabcli (Recommended)

```bash
# 1. Start the API (in one terminal)
tabcli dev start --api

# 2. Run E2E tests with auto-generated token (in another terminal)
tabcli dev e2e --e2e-test-token
```

This will:

1. Generate a test user and JWT token
2. Build the extension
3. Run E2E tests with the token as `E2E_TEST_TOKEN` env var

### Option B: Manual token management

```bash
# 1. Start the API
tabcli dev start --api

# 2. Generate and export the token
npm run db:seed:test -w api
export E2E_TEST_TOKEN=<paste token from output>

# 3. Run E2E tests
npm run test:e2e -w extension
```

## Running E2E Tests

### With real API (authenticated tests)

```bash
# Token must be set
npm run test:e2e -w extension
```

### Without real API (local-only tests)

```bash
# Tests that need API will be skipped
npm run test:e2e -w extension
```

## Test Behavior

| Token Present | API Available | Result                               |
| ------------- | ------------- | ------------------------------------ |
| Yes           | Yes           | Full tests run with API verification |
| Yes           | No            | Tests fail on API calls              |
| No            | -             | API-dependent tests skipped          |

## CI Pipeline

The GitHub Actions workflow automatically:

1. Starts Postgres & Redis services
2. Runs database migrations
3. Seeds test user and captures token
4. Starts API server
5. Runs E2E tests with token

No manual setup required for CI.

## Token Expiry

Tokens expire after **24 hours**. Regenerate with:

```bash
npm run db:seed:test -w api
```

## Troubleshooting

### "No E2E_TEST_TOKEN found"

Tests are running without API - this is normal for local-only mode.

### "API request failed"

1. Verify API is running: `curl http://localhost:8080/health`
2. Check token is valid (not expired)
3. Regenerate token if needed

### "Test user not found"

Run the seed script to create/update the test user:

```bash
npm run db:seed:test -w api
```

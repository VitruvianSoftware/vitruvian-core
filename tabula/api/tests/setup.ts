/**
 * Copyright (c) 2026 VitruvianSoftware
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
 */

/**
 * Global test setup for API tests
 */

// Test environment. Under Bazel (rules_itest service_test) the hermetic
// Postgres/Redis ports arrive via ASSIGNED_PORTS; outside Bazel fall back to
// the legacy local-dev defaults.
process.env.NODE_ENV = "test";
const assignedPorts = process.env.ASSIGNED_PORTS
  ? (JSON.parse(process.env.ASSIGNED_PORTS) as Record<string, number>)
  : null;
const pgPort = assignedPorts?.["@@//tabula/api:postgres"];
const redisPort = assignedPorts?.["@@//tabula/api:redis"];
process.env.DATABASE_URL = pgPort
  ? `postgresql://postgres@127.0.0.1:${pgPort}/postgres`
  : "postgresql://test:test@localhost:5432/tabula_test";
if (redisPort) {
  process.env.REDIS_URL = `redis://127.0.0.1:${redisPort}`;
}
process.env.JWT_SECRET = "test-secret-key-for-testing-only";
process.env.JWT_REFRESH_SECRET = "test-refresh-secret-key-for-testing-only";

// Set test timeout
jest.setTimeout(10000);

// Global test utilities
global.console = {
  ...console,
  // Suppress console.log in tests
  log: jest.fn(),
  debug: jest.fn(),
  info: jest.fn(),
  // Keep error and warn for debugging
  warn: console.warn,
  error: console.error,
};

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
 * Tests run on the original TypeScript through @swc/jest (Rust transform with
 * its own jest.mock hoisting; ts-jest would type-check-recompile per
 * short-lived Bazel action, and tsc-pre-transpiled JSX trips babel's
 * out-of-scope guard for jsx_runtime in jest.mock factories).
 * Type-checking is enforced separately by the :tests_lib ts_project.
 */
module.exports = {
  testEnvironment: "jsdom",
  setupFilesAfterEnv: ["<rootDir>/jest.setup.js"],
  // Keep resolved modules inside the runfiles symlink tree (symlinks:false) so
  // jest.mock() IDs and coverage attribution stay consistent under Bazel. See
  // jest-resolver.cjs for the full mechanism.
  resolver: "<rootDir>/../jest-resolver.cjs",
  testMatch: [
    "**/__tests__/**/*.ts",
    "**/__tests__/**/*.tsx",
    "**/?(*.)+(test).ts",
    "**/?(*.)+(test).tsx",
  ],
  testPathIgnorePatterns: ["/node_modules/", "/tests/e2e"],
  transform: {
    "^.+\\.(t|j)sx?$": [
      "@swc/jest",
      {
        jsc: {
          parser: { syntax: "typescript", tsx: true },
          transform: { react: { runtime: "automatic" } },
          target: "es2022",
        },
        module: { type: "commonjs" },
      },
    ],
  },
  collectCoverageFrom: [
    "src/**/*.{ts,tsx}",
    "!src/**/*.test.{ts,tsx}",
    "!src/**/__tests__/**",
    "!src/**/*.d.ts",
    "!src/testUtils/**",
  ],
  coverageThreshold: {
    global: {
      branches: 65, // Lower for UI complexity
      functions: 80,
      lines: 80,
      statements: 79,
    },
  },
  coverageDirectory: "coverage",
  coverageReporters: ["text", "lcov", "json", "json-summary", "html"],
  moduleNameMapper: {
    "\\.(css|less|scss|sass)$": "<rootDir>/tests/styleMock.js",
  },
};

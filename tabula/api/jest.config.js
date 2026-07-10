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

/** @type {import('jest').Config} */
/**
 * Tests run on the original TypeScript through @swc/jest (Rust transform with
 * its own jest.mock hoisting; ts-jest would type-check-recompile inside each
 * short-lived Bazel action). Type-checking is enforced separately by the
 * :tests_lib ts_project.
 */
module.exports = {
  testEnvironment: "node",
  roots: ["<rootDir>/tests", "<rootDir>/src"],
  testMatch: ["**/__tests__/**/*.ts", "**/?(*.)+(spec|test).ts"],
  // Keep resolved modules inside the runfiles symlink tree (symlinks:false) so
  // jest.mock() IDs and coverage attribution stay consistent under Bazel. This
  // replaces the earlier ts-first moduleFileExtensions workaround, which fixed
  // `bazel test` but not `bazel coverage`. See ../jest-resolver.cjs for the
  // full mechanism.
  resolver: "<rootDir>/../jest-resolver.cjs",
  transform: {
    "^.+\\.(t|j)s$": [
      "@swc/jest",
      {
        jsc: { parser: { syntax: "typescript" }, target: "es2022" },
        module: { type: "commonjs" },
      },
    ],
  },
  collectCoverageFrom: [
    "src/**/*.ts",
    "!src/**/*.d.ts",
    "!src/**/*.test.ts",
    "!src/**/*.spec.ts",
    "!src/types/**",
    "!src/app.ts", // Exclude server startup file from coverage
    "!src/lib/redis.ts", // Redis is optional and mocked in tests
    "!src/lib/prisma.ts", // Prisma client initialization
  ],
  coverageThreshold: {
    global: {
      branches: 70, // Realistic threshold considering optional features and error branches
      functions: 85,
      lines: 85,
      statements: 85,
    },
  },
  coverageDirectory: "coverage",
  coverageReporters: ["text", "lcov", "json", "json-summary", "html"],
  setupFilesAfterEnv: ["<rootDir>/tests/setup.ts"],
  testTimeout: 10000,
  verbose: true,
};

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

const nextJest = require("next/jest");

const createJestConfig = nextJest({
  // Path to the Next.js app, to load next.config.ts and .env in the test env.
  // Under Bazel (rules_jest) the process cwd is the runfiles root, so this is
  // workspace-relative rather than config-relative.
  dir: process.env.JS_BINARY__RUNFILES ? "tabula/web" : "./",
});

// Add any custom config to be passed to Jest
/** @type {import('jest').Config} */
const customJestConfig = {
  setupFilesAfterEnv: ["<rootDir>/jest.setup.js"],
  testEnvironment: "jest-environment-jsdom",
  // Keep resolved modules inside the runfiles symlink tree (symlinks:false) so
  // jest.mock() IDs and coverage attribution stay consistent under Bazel. See
  // ../jest-resolver.cjs for the full mechanism.
  resolver: "<rootDir>/../jest-resolver.cjs",
  collectCoverageFrom: [
    "app/**/*.{js,jsx,ts,tsx}",
    "lib/**/*.{js,jsx,ts,tsx}",
    "!**/*.d.ts",
    "!**/node_modules/**",
  ],
  coverageReporters: ["text", "lcov", "json", "json-summary", "html"],
  moduleNameMapper: {
    "^@/(.*)$": "<rootDir>/$1",
    "^geist/font/(.*)$": "<rootDir>/__mocks__/geistFont.js",
    "^@vitruviansoftware/design-system$": "<rootDir>/__mocks__/designSystem.js",
    "\\.css$": "<rootDir>/__mocks__/geistFont.js"
  },
};

// createJestConfig is exported this way to ensure that next/jest can load the Next.js config which is async.
// next/jest's generated transformIgnorePatterns only understands npm/pnpm
// store layouts; rewrite it for the rules_js virtual store
// (node_modules/.aspect_rules_js/<pkg>@<v>/node_modules/<pkg>) so ESM-only
// packages in transpilePackages (geist) are actually transformed.
module.exports = async () => {
  const config = await createJestConfig(customJestConfig)();
  config.transformIgnorePatterns = [
    "node_modules/(?!\\.aspect_rules_js|geist)",
    "^.+\\.module\\.(css|sass|scss)$",
  ];
  return config;
};

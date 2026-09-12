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

/** @type {import('ts-jest').JestConfigWithTsJest} */
const path = require("path");

module.exports = {
  preset: "ts-jest",
  testEnvironment: "node",
  testMatch: ["**/__tests__/**/*.test.ts"],
  // server/__tests__/server.test.ts previously depended on msw@2 (ESM-only),
  // whose deep .mjs transitive deps ts-jest/CJS could not transform in the
  // hermetic bazel sandbox, so it was skipped. It now mocks the server's
  // `node-fetch` calls directly via a pure-CJS fetch mock
  // (server/__tests__/fetch-mock.ts), so it runs in both pnpm and bazel.
  // fetch-mock.ts is a test helper, not a *.test.ts suite, so testMatch already
  // excludes it from being run as a suite.
  testPathIgnorePatterns: ["/node_modules/"],
  moduleNameMapper: {
    "^(\.{1,2}/.*)\.js$": "$1",
  },
  transform: {
    "^.+\\.[tj]s$": [
      "ts-jest",
      { tsconfig: path.resolve(__dirname, "tsconfig.test.json") },
    ],
  },
  // uuid >=11 ships ESM-only (no CJS export); let ts-jest transform it to CJS
  // (allowJs in tsconfig.test.json) instead of jest choking on its `export`.
  // Two path shapes must stay transformable: plain node_modules/uuid/ (npx
  // jest / the standalone mirror) AND Bazel's rules_js virtual store
  // (node_modules/.aspect_rules_js/uuid@<v>/node_modules/uuid/).
  transformIgnorePatterns: ["/node_modules/(?!(\.aspect_rules_js/)?uuid[@/])"],
};

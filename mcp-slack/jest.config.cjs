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
  testPathIgnorePatterns: ["/node_modules/", "/dist/"],
  // src/ uses ESM-style ".js" specifiers for its own relative imports (the
  // package is "type": "module"); strip them so ts-jest resolves the .ts files.
  moduleNameMapper: {
    "^(\\.{1,2}/.*)\\.js$": "$1",
  },
  // "ts" must precede "js". Under Bazel the ts_project's swc output lands at
  // the same relative path as the source (bazel-out/.../mcp-slack/src/*.js),
  // so with jest's default extension order a stripped specifier resolves to
  // the *compiled* file instead of the source — which then fails to parse.
  // Only modules with internal relative imports hit this, so it surfaces under
  // Bazel and not under `npx jest`.
  moduleFileExtensions: ["ts", "tsx", "js", "mjs", "cjs", "json", "node"],
  transform: {
    "^.+\\.[tj]s$": [
      "ts-jest",
      { tsconfig: path.resolve(__dirname, "tsconfig.test.json") },
    ],
  },
  // jose is ESM-only (no CJS export), so ts-jest must transform it to CJS
  // rather than jest choking on its `export` — same treatment oauth-user-
  // inspector gives uuid. Three path shapes have to stay transformable, and
  // missing any one of them fails only in the runner that uses it:
  //   plain            node_modules/jose/
  //   pnpm store       node_modules/.pnpm/jose@<v>/node_modules/jose/
  //   bazel rules_js   node_modules/.aspect_rules_js/jose@<v>/node_modules/jose/
  transformIgnorePatterns: [
    "/node_modules/(?!(\\.pnpm/|\\.aspect_rules_js/)?jose[@/])",
  ],
};

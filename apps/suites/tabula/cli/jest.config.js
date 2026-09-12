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
 * Tests run on the original TypeScript through @swc/jest (same rationale as
 * tabula/extension/jest.config.js). Type-checking is enforced separately by
 * the :tests_lib ts_project.
 */
module.exports = {
  restoreMocks: true,
  testEnvironment: "node",
  testMatch: ["**/?(*.)+(test).ts"],
  testPathIgnorePatterns: ["/node_modules/", "/dist/"],
  // Keep resolved modules inside the runfiles symlink tree (symlinks:false) so
  // jest.mock() IDs and coverage attribution stay consistent under Bazel,
  // replacing the earlier ts-first moduleFileExtensions workaround. See
  // ../jest-resolver.cjs for the full mechanism.
  resolver: "<rootDir>/../jest-resolver.cjs",
  // chalk 5 is ESM-only: exempt it from the node_modules transform skip so
  // @swc/jest converts it to CJS for the test runtime (the production CLI
  // runs on node >= 22.12, where require(esm) is native). The optional
  // .aspect_rules_js/ prefix matches the rules_js virtual store layout.
  transformIgnorePatterns: [
    "/node_modules/(?!(\\.aspect_rules_js/)?(chalk|commander)[@/])",
  ],
  transform: {
    "^.+\\.(t|j)s$": [
      "@swc/jest",
      {
        jsc: {
          parser: { syntax: "typescript" },
          target: "es2022",
        },
        module: { type: "commonjs" },
      },
    ],
  },
};

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
 * Jest resolver: keep resolved module paths INSIDE the runfiles symlink tree.
 *
 * jest 30 resolves modules with unrs-resolver (oxc), whose default
 * `symlinks: true` rewrites every resolved path to its real location. Under
 * Bazel + rules_js, first-party sources live in the runfiles tree as symlinks
 * that point into the shared bazel-out `bin/` tree, so realpath'ing lifts every
 * module OUT of runfiles and into `bin/`. That single behavior caused two
 * distinct jest-30 failures:
 *
 *   1. `bazel test`: a test's `jest.mock("../x")` registers the runfiles path
 *      while the module-under-test's own `import "../x"` (loaded via the
 *      realpath'd SUT) resolves to the `bin/` path. The module IDs diverge,
 *      every jest.mock() silently no-ops, real chrome/prisma/ioredis modules
 *      load, and their open handles hang the run to the bazel timeout. (Only
 *      manifests once a sibling ts_project has emitted compiled `.js` into the
 *      shared bin tree — which CI, building `//tabula/...`, always has.)
 *   2. `bazel coverage`: `collectCoverageFrom` globs sources at `rootDir`
 *      (runfiles, un-realpath'd) so coverage is seeded at runfiles paths, but
 *      executed modules are realpath'd to `bin/`. The two path spaces never
 *      meet, so every file reports 0% and the coverageThreshold gate fails.
 *
 * Forcing `symlinks: false` makes oxc resolve lexically through the symlink
 * tree (the same semantics rules_js already runs Node under via
 * `--preserve-symlinks-main`). Both resolution paths then stay in runfiles and
 * agree, fixing mocks and coverage attribution uniformly.
 *
 * BUT symlinks:false must be scoped to first-party imports only. rules_js's
 * pnpm virtual store (`.aspect_rules_js/<pkg>@<ver>/node_modules/<pkg>`) relies
 * on realpath to reach each package's co-located transitive deps — e.g.
 * `@jest/expect` finding its sibling `expect`. Disabling symlinks there breaks
 * node_modules resolution. First-party imports are always path specifiers
 * (relative `./`/`../` or absolute, incl. moduleNameMapper's `<rootDir>/...`),
 * while node_modules packages are bare specifiers. Gate on that: keep first-
 * party modules in runfiles (symlinks:false), let bare package specifiers
 * realpath into the store (default symlinks:true).
 */
function isPathRequest(request) {
  return (
    request.startsWith(".") ||
    request.startsWith("/") ||
    /^[A-Za-z]:[\\/]/.test(request) // Windows absolute
  );
}

module.exports = (request, options) =>
  isPathRequest(request)
    ? options.defaultResolver(request, { ...options, symlinks: false })
    : options.defaultResolver(request, options);

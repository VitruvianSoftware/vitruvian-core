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

// Guards against the class of failure that took prod down on 2026-06-27: a
// Dependabot bump moved `react` 18 -> 19 but left `react-dom` at 18. Because the
// Dockerfile installs with --no-frozen-lockfile, the build resolved React 19 +
// react-dom 18 — an unsupported pairing — and the app threw during
// ReactDOM.createRoot, rendering only the static index.html fallback. No existing
// test (all backend) or the HTTP-200 smoke check caught it.
//
// react and react-dom are released in lockstep and MUST share a major version;
// their @types must track it too. This asserts that at the source of truth
// (package.json), so a split is caught in CI before it can ship.

import * as fs from "fs";
import * as path from "path";

describe("frontend dependency consistency", () => {
  const pkg = JSON.parse(
    fs.readFileSync(path.resolve(__dirname, "../../package.json"), "utf8"),
  ) as {
    dependencies: Record<string, string>;
    devDependencies: Record<string, string>;
  };

  // Major version from a semver range like "^19.2.7" / "~18.2.0" / "19.2.7".
  const major = (range: string): string => {
    const m = range.match(/(\d+)\./);
    if (!m) throw new Error(`unparseable version range: ${range}`);
    return m[1];
  };

  const reactMajor = major(pkg.dependencies.react);

  it("react-dom shares react's major version (a mismatch breaks runtime mount)", () => {
    expect(major(pkg.dependencies["react-dom"])).toBe(reactMajor);
  });

  it("@types/react and @types/react-dom track the react major", () => {
    expect(major(pkg.devDependencies["@types/react"])).toBe(reactMajor);
    expect(major(pkg.devDependencies["@types/react-dom"])).toBe(reactMajor);
  });
});

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

// Every environment variable this server reads must be documented.
//
// This exists because of how the gap was found rather than as a general tidiness
// rule. MCP_TRANSPORT, PORT, OIDC_ISSUER and OIDC_PROJECT_ID went undocumented
// from the moment the HTTP transport was added — one of them crashloops the pod
// when absent — and nobody noticed for four PRs. It surfaced only as a
// side-effect of adding a *fifth* variable and going looking for where to
// document it.
//
// That is the part worth defending against: the gap was invisible precisely
// because it was a gap, and the next undocumented variable would be invisible
// in exactly the same way. A note in a review cannot catch that. Reading the
// two files and comparing them can.
//
// Verified against history rather than asserted: run on the README as it stood
// one commit before OIDC_ALLOWED_SUBJECTS, this reports all five missing names.

import { readFileSync } from "node:fs";
import { join } from "node:path";

const packageRoot = join(__dirname, "..");

function read(relativePath: string): string {
  return readFileSync(join(packageRoot, relativePath), "utf8");
}

/**
 * Every env var name `resolveConfig` reads.
 *
 * Derived from the source rather than maintained by hand — a hand-kept list is
 * one more thing that silently goes stale, which is the failure being fixed.
 * Two spellings, because config.ts uses both: direct property access for
 * optional values and a `required(env, "NAME", why)` helper for mandatory ones.
 */
function environmentVariablesRead(source: string): string[] {
  const names = new Set<string>();
  for (const match of source.matchAll(/env\.([A-Z][A-Z0-9_]+)/g)) {
    names.add(match[1]!);
  }
  for (const match of source.matchAll(
    /required\(\s*\n?\s*env,\s*\n?\s*"([A-Z0-9_]+)"/g
  )) {
    names.add(match[1]!);
  }
  return [...names].sort();
}

describe("every environment variable is documented", () => {
  const names = environmentVariablesRead(read("src/config.ts"));

  it("finds the variables config.ts actually reads", () => {
    // A guard on the guard: if the extraction silently matched nothing, the
    // documentation assertion below would pass vacuously and this file would
    // be one more test that cannot fail. These four are the mandatory ones on
    // their respective transports and cannot legitimately disappear.
    expect(names).toEqual(expect.arrayContaining([
      "SLACK_BOT_TOKEN",
      "SLACK_TEAM_ID",
      "MCP_TRANSPORT",
      "OIDC_ALLOWED_SUBJECTS",
    ]));
    expect(names.length).toBeGreaterThanOrEqual(8);
  });

  it("documents each of them in the README", () => {
    const readme = read("README.md");
    const undocumented = names.filter((name) => !readme.includes(name));
    expect(undocumented).toEqual([]);
  });
});

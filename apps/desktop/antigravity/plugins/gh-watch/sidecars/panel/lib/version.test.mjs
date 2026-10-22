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

// release-please updates .release-please-manifest.json, plugin.json,
// sidecars/panel/package.json and CHANGELOG.md in lockstep (see
// release-please-config.json and .github/workflows/release.yml). These checks
// keep the version files in step, so a release never ships without its notes.

import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";

const read = (path) =>
  readFileSync(new URL(`../../../${path}`, import.meta.url), "utf8");

const releasePleaseLayout = (text) =>
  JSON.stringify(JSON.parse(text), null, 2) + "\n";

const matchesHeading = (line, v) =>
  line === `## ${v}` ||
  line.startsWith(`## ${v} (`) ||
  line.startsWith(`## [${v}](`);

const version = JSON.parse(read("plugin.json")).version;

test("plugin.json carries a plain x.y.z version in release-please layout", () => {
  assert.match(version, /^\d+\.\d+\.\d+$/);
  const raw = read("plugin.json");
  assert.equal(raw, releasePleaseLayout(raw));
});

test("the changelog's newest section is the version in plugin.json", () => {
  const first = read("CHANGELOG.md")
    .split("\n")
    .find((line) => line.startsWith("## "));
  assert.ok(
    first && matchesHeading(first, version),
    `expected newest CHANGELOG heading to match ${version}, got ${first}`,
  );
});

test("the changelog section for this version is not empty", () => {
  const lines = read("CHANGELOG.md").split("\n");
  const start = lines.findIndex((line) => matchesHeading(line, version));
  assert.notEqual(start, -1);
  const rest = lines.slice(start + 1);
  const end = rest.findIndex((line) => line.startsWith("## "));
  const body = (end === -1 ? rest : rest.slice(0, end)).join("\n");
  assert.match(body, /\S/);
});

test("the panel's package.json names the same version in release-please layout", () => {
  const raw = read("sidecars/panel/package.json");
  assert.equal(JSON.parse(raw).version, version);
  assert.equal(raw, releasePleaseLayout(raw));
});

test("release-please manifest and config stay in lockstep with plugin.json", () => {
  const manifest = JSON.parse(read(".release-please-manifest.json"));
  assert.equal(manifest["apps/desktop/antigravity/plugins/gh-watch"], version);
  const config = JSON.parse(read("release-please-config.json"));
  const pkg = config.packages["apps/desktop/antigravity/plugins/gh-watch"];
  assert.ok(pkg);
  const extraPaths = (pkg["extra-files"] ?? []).map((e) => e.path);
  assert.deepEqual(extraPaths.sort(), [
    "plugin.json",
    "sidecars/panel/package.json",
  ]);
});

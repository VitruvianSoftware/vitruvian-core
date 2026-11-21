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

// Release-please layout for the Claude Code plugin: .claude-plugin/plugin.json, the
// manifest and the changelog's top section carry one version, and plugin.json is laid
// out the way release-please rewrites it (two-space JSON), so a release bump changes
// only the version line.

import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const PKG = "apps/claude-code/plugins/vitruvian-orchestrator";
const read = (rel) => readFileSync(join(here, rel), "utf8");

const pluginText = read(".claude-plugin/plugin.json");
const version = JSON.parse(pluginText).version;

test("plugin.json carries an X.Y.Z version in release-please layout", () => {
  assert.match(version, /^\d+\.\d+\.\d+$/);
  assert.equal(
    pluginText,
    JSON.stringify(JSON.parse(pluginText), null, 2) + "\n",
  );
});

test("the manifest records the same version", () => {
  assert.equal(JSON.parse(read(".release-please-manifest.json"))[PKG], version);
});

test("release-please bumps .claude-plugin/plugin.json and nothing else", () => {
  const entry = JSON.parse(read("release-please-config.json")).packages[PKG];
  assert.ok(entry, `missing ${PKG} in release-please-config.json`);
  assert.deepEqual(
    (entry["extra-files"] ?? []).map((f) => f.path),
    [".claude-plugin/plugin.json"],
  );
});

test("the changelog's top section is this version and has notes", () => {
  const lines = read("CHANGELOG.md").split("\n");
  const heads = lines.flatMap((l, i) => (l.startsWith("## ") ? [i] : []));
  assert.ok(heads.length > 0, "CHANGELOG.md has no ## version heading");
  const top = lines[heads[0]];
  assert.ok(
    top === `## ${version}` ||
      top.startsWith(`## ${version} (`) ||
      top.startsWith(`## [${version}](`),
    `top heading "${top}" does not match plugin.json ${version}`,
  );
  const body = lines.slice(heads[0] + 1, heads[1] ?? lines.length).join("\n");
  assert.ok(
    body.trim().length > 0,
    "top changelog section has no release notes",
  );
});

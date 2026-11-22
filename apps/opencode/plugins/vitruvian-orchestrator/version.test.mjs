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

// Release-please layout for the OpenCode plugin's npm package: package.json, the
// manifest and the changelog's top section carry one version, and the package
// ships what OpenCode loads (the ./server and ./tui exports, agents, skills).

import { test } from "node:test";
import assert from "node:assert/strict";
import { existsSync, readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const PKG = "apps/opencode/plugins/vitruvian-orchestrator";
const read = (rel) => readFileSync(join(here, rel), "utf8");

const pkg = JSON.parse(read("package.json"));
const version = pkg.version;

test("package.json is a public npm package with an X.Y.Z version", () => {
  assert.match(version, /^\d+\.\d+\.\d+$/);
  assert.equal(pkg.name, "@vitruviansoftware/opencode-vitruvian-orchestrator");
  assert.notEqual(pkg.private, true);
  assert.equal(pkg.license, "MIT");
  assert.equal(pkg.publishConfig?.access, "public");
});

test("the exports are the parts OpenCode loads, and they exist", () => {
  assert.deepEqual(pkg.exports, {
    "./server": "./server.mjs",
    "./tui": "./tui.tsx",
    "./package.json": "./package.json",
  });
  for (const file of Object.values(pkg.exports)) {
    assert.ok(existsSync(join(here, file)), `${file} is missing`);
  }
  for (const want of [
    "server.mjs",
    "tui.tsx",
    "lib/*.mjs",
    "!lib/*.test.mjs",
    "agents/*.md",
    "skills/*/SKILL.md",
    "LICENSE",
  ]) {
    assert.ok(pkg.files.includes(want), `files is missing ${want}`);
  }
});

test("the package has no runtime dependencies", () => {
  // OpenCode provides solid-js to the sidebar; anything npm would install
  // beside it is a second copy, and the mirror's publish has no build step.
  assert.equal(pkg.dependencies, undefined);
  assert.equal(pkg.peerDependencies, undefined);
});

test("the manifest records the same version", () => {
  assert.equal(JSON.parse(read(".release-please-manifest.json"))[PKG], version);
});

test("release-please bumps package.json as a node package", () => {
  const entry = JSON.parse(read("release-please-config.json")).packages[PKG];
  assert.ok(entry, `missing ${PKG} in release-please-config.json`);
  assert.equal(entry["release-type"], "node");
  assert.equal(entry["package-name"], pkg.name);
  assert.equal(entry.component, "vitruvian-orchestrator-opencode");
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
    `top heading "${top}" does not match package.json ${version}`,
  );
  const body = lines.slice(heads[0] + 1, heads[1] ?? lines.length).join("\n");
  assert.ok(
    body.trim().length > 0,
    "top changelog section has no release notes",
  );
});

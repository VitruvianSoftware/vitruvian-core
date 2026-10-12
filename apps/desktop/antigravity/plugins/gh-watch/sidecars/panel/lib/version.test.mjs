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

// A release is cut by changing the version in plugin.json (see
// .github/workflows/release.yml). These checks keep the other places that
// name the version in step, so a release never ships without its notes.

import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";

const read = (path) =>
  readFileSync(new URL(`../../../${path}`, import.meta.url), "utf8");

const version = JSON.parse(read("plugin.json")).version;

test("plugin.json carries a plain x.y.z version", () => {
  assert.match(version, /^\d+\.\d+\.\d+$/);
});

test("the changelog's newest section is the version in plugin.json", () => {
  const first = read("CHANGELOG.md")
    .split("\n")
    .find((line) => line.startsWith("## "));
  assert.equal(first, `## ${version}`);
});

test("the changelog section for this version is not empty", () => {
  const lines = read("CHANGELOG.md").split("\n");
  const start = lines.indexOf(`## ${version}`);
  const rest = lines.slice(start + 1);
  const end = rest.findIndex((line) => line.startsWith("## "));
  const body = (end === -1 ? rest : rest.slice(0, end)).join("\n");
  assert.match(body, /\S/);
});

test("the panel's package.json names the same version", () => {
  assert.equal(
    JSON.parse(read("sidecars/panel/package.json")).version,
    version,
  );
});

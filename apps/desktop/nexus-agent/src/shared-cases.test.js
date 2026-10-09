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

// The examples in ../testdata are shared with the Mac apps' tests
// (macos/Tests/SharedCasesTests.swift). This file runs them through the bot's
// own code, so a rule changed here without the apps following fails their
// tests, and the other way round. Expected values live only in the JSON.

import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";

import { annotationIsArchived } from "./annotations.js";

/**
 * The cases of one shared file. A missing, unreadable or empty file fails the
 * test: a loop over no cases would pass without checking anything.
 * @param {string} file
 * @returns {any[]}
 */
function loadCases(file) {
  const url = new URL(`../testdata/${file}`, import.meta.url);
  let parsed;
  try {
    parsed = JSON.parse(fs.readFileSync(url, "utf8"));
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    assert.fail(`shared cases file ${url.pathname} cannot be read: ${message}`);
  }
  assert.ok(
    Array.isArray(parsed.cases) && parsed.cases.length > 0,
    `shared cases file ${url.pathname} has no cases`,
  );
  return parsed.cases;
}

test("archive annotations: the bot reads every shared example as written", () => {
  const cases = loadCases("archive-annotations.json");
  let checked = 0;
  for (const { name, text, archived } of cases) {
    assert.equal(typeof archived, "boolean", `${name}: archived is a boolean`);
    assert.equal(annotationIsArchived(text), archived, name);
    checked += 1;
  }
  assert.equal(checked, cases.length);
});

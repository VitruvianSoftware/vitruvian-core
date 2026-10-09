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
import os from "node:os";
import path from "node:path";

// The package the bot loads `.env` with (bot.js: `import "dotenv/config"`).
import dotenv from "dotenv";

import { annotationIsArchived } from "./annotations.js";

// agy.js reads the environment once, when it is imported, and loads the
// session store from the working directory. Point it at a throwaway folder
// and take the approval-mode keys out BEFORE importing, so the test never
// touches a real store and sees the bot as it is with no mode in `.env`.
process.env.AGY_WORKING_DIR = fs.mkdtempSync(
  path.join(os.tmpdir(), "nexus-shared-cases-"),
);
delete process.env.AGY_APPROVAL_MODE;
delete process.env.GEMINI_APPROVAL_MODE;
const { approvalArgs, getChatSettings } = await import("./agy.js");

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

test("approval modes: the bot passes agy the flags every shared example says", () => {
  const cases = loadCases("approval-modes.json");
  // A chat nobody has changed the mode for: its mode is whatever the bot took
  // from the environment when it loaded, which here had no mode in it.
  const whenAbsent = getChatSettings(0).approvalMode;
  let checked = 0;
  for (const { name, value, args } of cases) {
    assert.ok(Array.isArray(args), `${name}: args is a list`);
    assert.ok(
      value === null || typeof value === "string",
      `${name}: value is a string, or null for an absent key`,
    );
    const mode = value === null ? whenAbsent : value;
    assert.deepEqual(approvalArgs(mode), args, name);
    checked += 1;
  }
  assert.equal(checked, cases.length);
});

test(".env lines: dotenv reads every shared example as written", () => {
  const cases = loadCases("env-lines.json");
  let checked = 0;
  for (const { name, line, key, value } of cases) {
    assert.equal(typeof line, "string", `${name}: line is a string`);
    assert.ok(
      (key === null && value === null) ||
        (typeof key === "string" && typeof value === "string"),
      `${name}: key and value are both strings, or both null`,
    );
    const expected = key === null ? {} : { [key]: value };
    assert.deepEqual(dotenv.parse(line), expected, name);
    checked += 1;
  }
  assert.equal(checked, cases.length);
});

test(".env values: what the apps write, dotenv reads back as the same value", () => {
  const cases = loadCases("env-written-values.json");
  let checked = 0;
  for (const { name, value, line, lossy } of cases) {
    assert.equal(typeof value, "string", `${name}: value is a string`);
    assert.equal(typeof line, "string", `${name}: line is a string`);
    const read = dotenv.parse(`K=${line}`).K;
    if (lossy === true) {
      // No spelling carries this value. The day one does, this fails, and
      // the case loses its `lossy` mark.
      assert.notEqual(read, value, `${name}: marked lossy, but it reads back`);
    } else {
      assert.equal(lossy, undefined, `${name}: lossy is true or left out`);
      assert.equal(read, value, name);
    }
    checked += 1;
  }
  assert.equal(checked, cases.length);
});

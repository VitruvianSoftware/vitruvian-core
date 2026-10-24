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

import assert from "node:assert/strict";
import { test } from "node:test";

import {
  compileToHtml,
  escapeHtml,
  openuiLiteral,
  parseOpenUILang,
  resolveDataPath,
  toOpenUILang,
} from "./openui.mjs";

function parts(dsl) {
  const { root } = parseOpenUILang(dsl);
  assert.equal(root.$component, "Card");
  const [header, grid, table] = root.args[0];
  const columns = Object.fromEntries(
    table.args[0].map((col) => [col.args[0], col.args[1]]),
  );
  return { root, header, grid, table, columns };
}

test("parseOpenUILang resolves bindings and forward references", () => {
  const parsed = parseOpenUILang(`
    root = Card([hdr, Kpi("Findings", 0, "clean", "success", 100)])
    hdr = Header("Security Guidance", "v0.1.0", "clean", "success")
  `);
  assert.deepEqual(parsed.order, ["root", "hdr"]);
  assert.equal(parsed.root.$component, "Card");
});

test("resolveDataPath plucks array columns", () => {
  const ctx = {
    data: {
      findings: [{ ruleId: "js-eval" }, { ruleId: "sql-string-concat" }],
    },
  };
  assert.deepEqual(resolveDataPath(ctx, "data.findings.ruleId"), [
    "js-eval",
    "sql-string-concat",
  ]);
});

test("compileToHtml renders components and escapes HTML", () => {
  const html = compileToHtml(
    `root = Card([Header("Security Guidance", "v0.1.0"), TextContent("<img onerror=alert(1)>")])`,
    { title: "Security" },
  );
  assert.match(html, /^<!DOCTYPE html>/);
  assert.ok(!html.includes("<img onerror"));
  assert.equal(escapeHtml(null), "");
  assert.equal(openuiLiteral(42), "42");
});

test("toOpenUILang gives a valid, clean document for an empty state", () => {
  for (const state of [undefined, null, {}]) {
    const dsl = toOpenUILang(state);
    const { header, grid, columns } = parts(dsl);
    assert.deepEqual(header, {
      $component: "Header",
      args: ["Security Guidance", "", "clean", "success"],
    });
    assert.equal(grid.args[0], 4);
    assert.deepEqual(columns, {
      Rule: [],
      Location: [],
      Severity: [],
      CWE: [],
    });
  }
});

test("toOpenUILang summarises populated findings and suppressions", () => {
  const dsl = toOpenUILang({
    version: "0.1.0",
    findings: [
      {
        ruleId: "aws-access-key",
        filePath: "config.js",
        line: 12,
        severity: "critical",
        cwe: "CWE-798",
      },
      {
        ruleId: "js-eval",
        filePath: "index.js",
        line: 30,
        severity: "high",
        cwe: "CWE-95",
      },
    ],
    suppressions: ["dom-xss-innerhtml:old.js:4"],
  });
  const { header, columns } = parts(dsl);
  assert.deepEqual(header.args, [
    "Security Guidance",
    "v0.1.0",
    "1 critical",
    "danger",
  ]);
  assert.deepEqual(columns.Rule, ["aws-access-key", "js-eval"]);
  assert.deepEqual(columns.Location, ["config.js:12", "index.js:30"]);
  assert.deepEqual(columns.Severity, ["✗ critical", "✗ high"]);
  assert.deepEqual(columns.CWE, ["CWE-798", "CWE-95"]);
});

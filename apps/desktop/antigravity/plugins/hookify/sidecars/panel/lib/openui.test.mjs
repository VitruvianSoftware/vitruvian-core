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

test("parseOpenUILang resolves bindings, forward references and literals", () => {
  const parsed = parseOpenUILang(`
    root = Card([title, Kpi("Rules", 4, "active", "success", 80)])
    title = Header("Hookify", "v0.1.0", "4 active", "success")
  `);
  assert.deepEqual(parsed.order, ["root", "title"]);
  assert.equal(parsed.root.$component, "Card");
});

test("resolveDataPath walks objects and plucks columns through arrays", () => {
  const ctx = {
    data: {
      rows: [
        { rule: "a", hits: 1 },
        { rule: "b", hits: 2 },
      ],
    },
  };
  assert.deepEqual(resolveDataPath(ctx, "data.rows.rule"), ["a", "b"]);
});

test("compileToHtml renders components and escapes unsafe HTML", () => {
  const html = compileToHtml(
    `root = Card([Header("Hookify", "v0.1.0"), TextContent("<script>alert(1)</script>")])`,
    { title: "<b>Hookify</b>" },
  );
  assert.match(html, /^<!DOCTYPE html>/);
  assert.ok(!html.includes("<script>alert(1)"));
  assert.match(html, /&lt;script&gt;alert\(1\)&lt;\/script&gt;/);
  assert.equal(escapeHtml(null), "");
  assert.equal(openuiLiteral("x\ny"), '"x\\ny"');
});

test("toOpenUILang gives a valid, zeroed document for an empty state", () => {
  for (const state of [undefined, null, {}]) {
    const dsl = toOpenUILang(state);
    const { header, grid, columns } = parts(dsl);
    assert.deepEqual(header, {
      $component: "Header",
      args: ["Hookify", "", "idle", "neutral"],
    });
    assert.equal(grid.args[0], 4);
    assert.deepEqual(columns, {
      Rule: [],
      Event: [],
      Action: [],
      Status: [],
    });
  }
});

test("toOpenUILang summarises populated rules and events", () => {
  const dsl = toOpenUILang({
    version: "0.1.0",
    rules: [
      { name: "block-rm", event: "bash", action: "block", enabled: true },
      {
        name: "rewrite-npm",
        event: "bash",
        action: "overwrite",
        enabled: true,
      },
      { name: "old-rule", event: "Stop", action: "warn", enabled: false },
    ],
    events: [
      { decision: "deny" },
      { decision: "ask" },
      { decision: "overwrite" },
    ],
  });
  const { header, columns } = parts(dsl);
  assert.deepEqual(header.args, ["Hookify", "v0.1.0", "1 blocked", "danger"]);
  assert.deepEqual(columns.Rule, ["block-rm", "rewrite-npm", "old-rule"]);
  assert.deepEqual(columns.Status, ["✗ blocking", "• rewrite", "• disabled"]);
});

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

const SAMPLE = {
  version: "0.1.0",
  report: {
    totals: {
      conversations: 3,
      projects: 2,
      userPrompts: 8,
      plannerTurns: 18,
      toolCalls: 42,
      subagents: 2,
      commits: 4,
      prs: 2,
      truncatedSteps: 3,
      errors: 1,
    },
    projects: [
      {
        project: "vitruvian-core",
        conversations: 2,
        userPrompts: 6,
        plannerTurns: 14,
        toolCalls: 34,
        subagents: 2,
        commits: 3,
        prs: 2,
        truncatedSteps: 3,
        errors: 0,
      },
      {
        project: "nexus-agent",
        conversations: 1,
        userPrompts: 2,
        plannerTurns: 4,
        toolCalls: 8,
        subagents: 0,
        commits: 1,
        prs: 0,
        truncatedSteps: 0,
        errors: 1,
      },
    ],
  },
  hotspots: [
    {
      conversationId: "conv-1",
      project: "vitruvian-core",
      severity: "warning",
      kind: "truncation",
      summary: "3 truncated steps",
    },
  ],
};

test("parseOpenUILang resolves bindings, forward references and literals", () => {
  const parsed = parseOpenUILang(`
    # a comment
    root = Card([title, Kpi("Count", 3, "sub", "info", 50)])
    title = Header("Hi", "v1", "ok", "success") // trailing comment
  `);
  assert.deepEqual(parsed.order, ["root", "title"]);
  assert.deepEqual(parsed.root, {
    $component: "Card",
    args: [
      [
        { $component: "Header", args: ["Hi", "v1", "ok", "success"] },
        { $component: "Kpi", args: ["Count", 3, "sub", "info", 50] },
      ],
    ],
  });
});

test("resolveDataPath walks objects and plucks columns through arrays", () => {
  const ctx = {
    data: {
      rows: [
        { month: "Jan", n: 1 },
        { month: "Feb", n: 2 },
      ],
    },
    a: { b: { c: 7 } },
  };
  assert.equal(resolveDataPath(ctx, "a.b.c"), 7);
  assert.deepEqual(resolveDataPath(ctx, "data.rows.month"), ["Jan", "Feb"]);
  assert.equal(resolveDataPath(null, "a"), undefined);
});

test("compileToHtml renders components and escapes unsafe HTML", () => {
  const html = compileToHtml(
    `root = Card([Header("Receipts", "v0.1.0"), TextContent("<script>alert(1)</script>")])`,
    { title: "<b>Receipts</b>", footer: "exported" },
  );
  assert.match(html, /^<!DOCTYPE html>/);
  assert.ok(!html.includes("<script>alert(1)"));
  assert.match(html, /&lt;script&gt;alert\(1\)&lt;\/script&gt;/);
  assert.equal(escapeHtml(null), "");
  assert.equal(openuiLiteral("a\nb"), '"a\\nb"');
});

test("toOpenUILang gives a valid, zeroed document for an empty state", () => {
  for (const state of [undefined, null, {}, { report: null }]) {
    const dsl = toOpenUILang(state);
    const { header, grid, columns } = parts(dsl);
    assert.deepEqual(header, {
      $component: "Header",
      args: ["Receipts Report", "", "idle", "neutral"],
    });
    assert.equal(grid.args[0], 4);
    assert.deepEqual(columns, {
      Project: [],
      Sessions: [],
      "Tools & Turns": [],
      Shipped: [],
      Status: [],
    });
  }
});

test("toOpenUILang summarises a populated receipts state", () => {
  const dsl = toOpenUILang(SAMPLE);
  assert.match(
    dsl,
    /^# receipts-report state as OpenUI Lang v0\.5\nroot = Card\(\[/,
  );
  const { header, grid, columns } = parts(dsl);
  assert.deepEqual(header.args, [
    "Receipts Report",
    "v0.1.0",
    "1 hotspot",
    "warning",
  ]);
  const kpis = Object.fromEntries(grid.args[1].map((k) => [k.args[0], k.args]));
  assert.deepEqual(kpis.Sessions, [
    "Sessions",
    3,
    "2 projects · 8 prompts",
    "info",
  ]);
  assert.deepEqual(kpis["Tool Calls"], [
    "Tool Calls",
    42,
    "18 turns · 2 subagents",
    "info",
  ]);
  assert.deepEqual(kpis.Shipped, [
    "Shipped",
    6,
    "4 commits · 2 PRs",
    "success",
  ]);
  assert.deepEqual(kpis.Hotspots, [
    "Hotspots",
    1,
    "3 truncated · 1 errors",
    "warning",
  ]);
  assert.deepEqual(columns.Project, ["vitruvian-core", "nexus-agent"]);
  assert.deepEqual(columns.Status, ["• 3 truncated", "✗ 1 error"]);
});

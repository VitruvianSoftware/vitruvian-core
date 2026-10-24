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
    # comment
    root = Card([title, Kpi("Subagents", 2, "1 running", "info", 50)])
    title = Header("Savvy Fleet", "v0.1.0", "1 running", "info")
  `);
  assert.deepEqual(parsed.order, ["root", "title"]);
  assert.equal(parsed.root.$component, "Card");
  assert.equal(parsed.root.args[0][0].$component, "Header");
});

test("resolveDataPath walks objects and plucks columns through arrays", () => {
  const ctx = {
    data: {
      rows: [
        { agent: "wren", tier: "medium" },
        { agent: "scout", tier: "light" },
      ],
    },
  };
  assert.deepEqual(resolveDataPath(ctx, "data.rows.agent"), ["wren", "scout"]);
});

test("compileToHtml renders components and escapes unsafe HTML", () => {
  const html = compileToHtml(
    toOpenUILang({
      version: "0.1.0",
      subagents: [
        {
          type: "wren",
          tier: "medium",
          role: "<script>alert(1)</script>",
          status: "running",
        },
      ],
    }),
    { title: "Savvy Fleet", footer: "fleet-footer" },
  );
  assert.match(html, /^<!DOCTYPE html>/);
  assert.ok(!html.includes("<script>alert(1)"));
  assert.match(html, /&lt;script&gt;alert\(1\)&lt;\/script&gt;/);
  assert.equal(escapeHtml(null), "");
  assert.equal(openuiLiteral("a\nb"), '"a\\nb"');
});

test("toOpenUILang gives a valid zeroed document for an empty state", () => {
  for (const state of [undefined, null, {}]) {
    const dsl = toOpenUILang(state);
    const { header, grid, table, columns } = parts(dsl);
    assert.deepEqual(header, {
      $component: "Header",
      args: ["Savvy Fleet", "", "idle", "neutral"],
    });
    assert.equal(grid.$component, "Grid");
    assert.equal(grid.args[0], 4);
    assert.equal(table.$component, "Table");
    assert.deepEqual(columns, {
      Subagent: [],
      Tier: [],
      Role: [],
      Status: [],
    });
  }
});

test("toOpenUILang summarises a populated fleet state", () => {
  const dsl = toOpenUILang({
    version: "0.1.0",
    flow: { title: "Extensions Suite", phase: "delegate", isFinished: false },
    totalSteps: 14,
    toolCalls: 9,
    totals: { formattedCost: "$0.42", formattedTokens: "18k" },
    subagents: [
      {
        type: "wren",
        tier: "medium",
        role: "Build savvy-fleet",
        status: "running",
      },
      {
        type: "scout",
        tier: "light",
        role: "Run unit tests",
        status: "done",
      },
    ],
    planned: [
      {
        specialist: "aegis",
        tier: "careful",
        title: "Security review",
      },
    ],
  });
  assert.match(
    dsl,
    /^# savvy-fleet state as OpenUI Lang v0\.5\nroot = Card\(\[/,
  );
  const { header, grid, columns } = parts(dsl);
  assert.deepEqual(header.args, ["Savvy Fleet", "v0.1.0", "1 running", "info"]);
  const kpis = Object.fromEntries(grid.args[1].map((k) => [k.args[0], k.args]));
  assert.deepEqual(kpis.Phase, [
    "Phase",
    "delegate",
    "Extensions Suite",
    "purple",
  ]);
  assert.deepEqual(kpis.Subagents, [
    "Subagents",
    2,
    "1 running · 1 done · 1 planned",
    "info",
  ]);
  assert.deepEqual(columns.Subagent, ["wren", "scout", "aegis"]);
  assert.deepEqual(columns.Tier, ["medium", "light", "careful"]);
  assert.deepEqual(columns.Role, [
    "Build savvy-fleet",
    "Run unit tests",
    "Security review",
  ]);
  assert.deepEqual(columns.Status, ["• running", "✓ done", "• planned"]);
});

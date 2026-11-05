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
    root = Card([title, Kpi("Catalog", 9, "Vitruvian", "info", 100)])
    title = Header("Extensions Marketplace", "v0.1.0", "2 enabled", "success")
  `);
  assert.deepEqual(parsed.order, ["root", "title"]);
  assert.equal(parsed.root.$component, "Card");
});

test("resolveDataPath walks objects and plucks columns through arrays", () => {
  const ctx = {
    data: {
      rows: [
        { id: "gh-watch", enabled: true },
        { id: "savvy-fleet", enabled: false },
      ],
    },
  };
  assert.deepEqual(resolveDataPath(ctx, "data.rows.id"), [
    "gh-watch",
    "savvy-fleet",
  ]);
});

test("compileToHtml renders components and escapes unsafe HTML", () => {
  const html = compileToHtml(
    toOpenUILang({
      version: "0.1.0",
      plugins: [
        {
          id: "<img src=x onerror=alert(1)>",
          category: "Security",
          installed: true,
          enabled: true,
        },
      ],
    }),
    { title: "Marketplace", footer: "mkt-footer" },
  );
  assert.match(html, /^<!DOCTYPE html>/);
  assert.ok(!html.includes("<img src=x"));
  assert.match(html, /&lt;img src=x onerror=alert\(1\)&gt;/);
  assert.equal(escapeHtml(null), "");
  assert.equal(openuiLiteral("a\tb"), '"a\\tb"');
});

test("toOpenUILang gives a valid zeroed document for an empty state", () => {
  for (const state of [undefined, null, {}]) {
    const dsl = toOpenUILang(state);
    const { header, grid, table, columns } = parts(dsl);
    assert.deepEqual(header, {
      $component: "Header",
      args: ["Extensions Marketplace", "", "idle", "neutral"],
    });
    assert.equal(grid.$component, "Grid");
    assert.equal(grid.args[0], 4);
    assert.equal(table.$component, "Table");
    assert.deepEqual(columns, {
      Extension: [],
      Category: [],
      Capabilities: [],
      Status: [],
    });
  }
});

test("toOpenUILang summarises a populated marketplace state", () => {
  const dsl = toOpenUILang({
    version: "0.1.0",
    plugins: [
      {
        id: "gh-watch",
        category: "CI & GitHub",
        installed: true,
        enabled: true,
        hasSidecarUi: true,
        hooks: ["gh-watch-signup"],
        rules: ["AGENTS.md"],
      },
      {
        id: "savvy-fleet",
        category: "Subagents",
        installed: true,
        enabled: false,
        hasSidecarUi: true,
        skills: ["savvy-flow", "savvy-fleet"],
      },
      {
        id: "ralph-loop",
        category: "Autonomous Loops",
        installed: false,
        enabled: false,
        hasSidecarUi: true,
      },
    ],
  });
  assert.match(
    dsl,
    /^# ext-marketplace state as OpenUI Lang v0\.5\nroot = Card\(\[/,
  );
  const { header, grid, columns } = parts(dsl);
  assert.deepEqual(header.args, [
    "Extensions Marketplace",
    "v0.1.0",
    "1 enabled",
    "success",
  ]);
  const kpis = Object.fromEntries(grid.args[1].map((k) => [k.args[0], k.args]));
  assert.deepEqual(kpis.Catalog, [
    "Catalog",
    3,
    "Vitruvian & official plugins",
    "info",
  ]);
  assert.deepEqual(kpis.Installed, [
    "Installed",
    2,
    "1 available to install",
    "info",
  ]);
  assert.deepEqual(columns.Extension, [
    "gh-watch",
    "savvy-fleet",
    "ralph-loop",
  ]);
  assert.deepEqual(columns.Capabilities, [
    "sidecar · 1 hook · 1 rule",
    "sidecar · 2 skills",
    "sidecar",
  ]);
  assert.deepEqual(columns.Status, ["✓ enabled", "• disabled", "available"]);
});

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
  worktrees: [
    {
      root: "/ws/wt-1",
      branch: "feat-alpha",
      isLinked: true,
      pr: {
        number: 101,
        state: "MERGED",
        checks: { passed: 5, failed: 0, running: 0, total: 5 },
      },
      treeKb: 2048,
      caches: [{ path: "/cache/1", kb: 4096 }],
      cleanup: "ready",
      note: "",
    },
    {
      root: "/ws/wt-2",
      branch: "fix-beta",
      isLinked: true,
      pr: {
        number: 102,
        state: "OPEN",
        checks: { passed: 2, failed: 1, running: 0, total: 3 },
      },
      treeKb: 1024,
      caches: [],
      cleanup: "none",
      note: "",
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
  };
  assert.deepEqual(resolveDataPath(ctx, "data.rows.month"), ["Jan", "Feb"]);
  assert.deepEqual(resolveDataPath(ctx, "data.rows.n"), [1, 2]);
});

test("compileToHtml renders components and escapes unsafe HTML", () => {
  const html = compileToHtml(
    `root = Card([TextContent("<img src=x onerror=alert(1)> & 'q'")])`,
    { title: "<b>t</b>", footer: '"f"' },
  );
  assert.match(html, /^<!DOCTYPE html>/);
  assert.ok(!html.includes("<img src=x"));
  assert.match(html, /&lt;img src=x onerror=alert\(1\)&gt; &amp; &#39;q&#39;/);
  assert.equal(escapeHtml(null), "");
  assert.equal(openuiLiteral("a\nb"), '"a\\nb"');
});

test("toOpenUILang gives a valid, zeroed document for an empty state", () => {
  for (const state of [undefined, null, {}, { worktrees: null }]) {
    const dsl = toOpenUILang(state);
    const { header, grid, table, columns } = parts(dsl);
    assert.deepEqual(header, {
      $component: "Header",
      args: ["Worktree Band", "", "idle", "neutral"],
    });
    assert.equal(grid.$component, "Grid");
    assert.equal(grid.args[0], 4);
    assert.equal(table.$component, "Table");
    assert.deepEqual(columns, {
      Branch: [],
      PR: [],
      Disk: [],
      Cleanup: [],
    });
  }
});

test("toOpenUILang summarises a populated worktree-band state", () => {
  const dsl = toOpenUILang(SAMPLE);
  assert.match(
    dsl,
    /^# worktree-band state as OpenUI Lang v0\.5\nroot = Card\(\[/,
  );
  const { header, grid, columns } = parts(dsl);
  assert.deepEqual(header.args, [
    "Worktree Band",
    "v0.1.0",
    "1 ready to clean",
    "success",
  ]);
  const kpis = Object.fromEntries(grid.args[1].map((k) => [k.args[0], k.args]));
  assert.deepEqual(kpis.Worktrees, [
    "Worktrees",
    2,
    "2 linked · 1 merged",
    "info",
  ]);
  assert.deepEqual(kpis["Ready to Clean"], [
    "Ready to Clean",
    1,
    "6 MB reclaimable",
    "success",
  ]);
  assert.deepEqual(kpis["Worktree Disk"], [
    "Worktree Disk",
    "3 MB",
    "active checkouts",
    "info",
  ]);
  assert.deepEqual(kpis["Bazel Disk"], [
    "Bazel Disk",
    "4 MB",
    "isolated output bases",
    "warning",
  ]);
  assert.deepEqual(columns.Branch, ["feat-alpha", "fix-beta"]);
  assert.deepEqual(columns.PR, ["✓ #101 merged", "✗ #102 (1 failed)"]);
  assert.deepEqual(columns.Disk, [
    "tree 2 MB · bazel 4 MB",
    "tree 1 MB · bazel none",
  ]);
  assert.deepEqual(columns.Cleanup, ["✓ ready to clean", "active"]);
});

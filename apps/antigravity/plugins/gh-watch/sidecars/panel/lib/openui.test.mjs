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

// The parts of a parsed toOpenUILang document, by position.
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
  version: "1.4.0",
  pace: { mode: "fast", reason: "panel open", intervalSeconds: 15 },
  flaky: [{ repo: "acme/web", name: "e2e", count: 3 }],
  lists: { reviews: { items: [{ repo: "acme/web", number: 9 }] } },
  watches: [
    {
      key: "acme/api#7",
      repo: "acme/api",
      number: 7,
      title: "feat: thing",
      addedAt: 1,
      counts: { pass: 8, fail: 0, pending: 0 },
      failing: [],
      queued: true,
      queuePosition: 2,
    },
    {
      key: "acme/web#12",
      repo: "acme/web",
      number: 12,
      title: "fix: lint",
      addedAt: 2,
      counts: { pass: 5, fail: 1, pending: 0 },
      failing: ["lint"],
    },
    {
      key: "acme/web#3",
      repo: "acme/web",
      number: 3,
      title: "old",
      addedAt: 3,
      closed: true,
      prState: "MERGED",
      counts: { pass: 4, fail: 0, pending: 0 },
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

test("parseOpenUILang reads escapes, booleans, null, negatives and concatenation", () => {
  const { root } = parseOpenUILang(
    String.raw`root = X("a\"b\\c\nd\te", true, false, null, -2.5, "x" + "y")`,
  );
  assert.deepEqual(root.args, ['a"b\\c\nd\te', true, false, null, -2.5, "xy"]);
});

test("parseOpenUILang takes a bare expression as root and survives empty input", () => {
  assert.equal(parseOpenUILang('Badge("hi")').root.$component, "Badge");
  assert.equal(parseOpenUILang("").root, null);
  assert.equal(parseOpenUILang(undefined).root, null);
});

test("parseOpenUILang resolves dotted references from data", () => {
  const { root } = parseOpenUILang('root = Col("Month", data.rows.month)', {
    rows: [{ month: "Jan" }, { month: "Feb" }],
  });
  assert.deepEqual(root.args, ["Month", ["Jan", "Feb"]]);
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
  assert.deepEqual(resolveDataPath(ctx, "data.rows.n"), [1, 2]);
  assert.equal(resolveDataPath(ctx, "a.missing.c"), undefined);
  assert.equal(resolveDataPath(null, "a"), undefined);
});

test("compileToHtml renders components into a full HTML page", () => {
  const html = compileToHtml(
    'root = Card([Header("Board", "v2"), Grid(4, [Kpi("Open", 3)]), Table([Col("PR", ["a#1", "b#2"])])])',
    { title: "My board", footer: "made here" },
  );
  assert.match(html, /^<!DOCTYPE html>/);
  assert.match(html, /<title>My board<\/title>/);
  for (const name of ["Card", "Header", "Grid", "Kpi", "Table"]) {
    assert.match(html, new RegExp(`data-openui-component="${name}"`));
  }
  assert.match(html, />a#1</);
  assert.match(html, />b#2</);
  assert.match(html, /made here/);
});

test("compileToHtml escapes text from the document and from options", () => {
  const html = compileToHtml(
    `root = Card([TextContent("<img src=x onerror=alert(1)> & 'q'")])`,
    { title: "<b>t</b>", footer: '"f"' },
  );
  assert.ok(!html.includes("<img src=x"), "raw markup leaked into the page");
  assert.ok(!html.includes("<b>t</b>"));
  assert.match(html, /&lt;img src=x onerror=alert\(1\)&gt; &amp; &#39;q&#39;/);
  assert.match(html, /<title>&lt;b&gt;t&lt;\/b&gt;<\/title>/);
  assert.match(html, /&quot;f&quot;/);
  assert.equal(escapeHtml(null), "");
});

test("openuiLiteral quotes strings and keeps readable numbers", () => {
  assert.equal(openuiLiteral(3), "3");
  assert.equal(openuiLiteral(-1.5), "-1.5");
  assert.equal(openuiLiteral(Number.NaN), '"NaN"');
  assert.equal(openuiLiteral(1e21), '"1e+21"');
  assert.equal(openuiLiteral(true), "true");
  assert.equal(openuiLiteral(null), "null");
  assert.equal(openuiLiteral(undefined), "null");
  assert.equal(openuiLiteral('a"b\\c\r\nd\te'), String.raw`"a\"b\\c\nd\te"`);
});

test("toOpenUILang gives a valid, zeroed document for an empty or missing state", () => {
  for (const state of [
    undefined,
    null,
    {},
    { watches: null, flaky: "x", pace: 3 },
  ]) {
    const dsl = toOpenUILang(state);
    const { header, grid, table, columns } = parts(dsl);
    assert.deepEqual(header, {
      $component: "Header",
      args: ["GH Watch", "", "idle", "neutral"],
    });
    assert.equal(grid.$component, "Grid");
    assert.equal(grid.args[0], 4);
    assert.deepEqual(
      grid.args[1].map((k) => [k.$component, k.args[0], k.args[1]]),
      [
        ["Kpi", "Watched PRs", 0],
        ["Kpi", "Failing", 0],
        ["Kpi", "Flaky checks", 0],
        ["Kpi", "Pace", "—"],
      ],
    );
    assert.equal(table.$component, "Table");
    assert.deepEqual(columns, { PR: [], Title: [], Status: [], Checks: [] });
  }
});

test("toOpenUILang summarises a populated state", () => {
  const dsl = toOpenUILang(SAMPLE);
  assert.match(dsl, /^# gh-watch state as OpenUI Lang v0\.5\nroot = Card\(\[/);
  const { header, grid, columns } = parts(dsl);
  assert.deepEqual(header.args, ["GH Watch", "v1.4.0", "1 failing", "danger"]);
  const kpis = Object.fromEntries(grid.args[1].map((k) => [k.args[0], k.args]));
  assert.deepEqual(kpis["Watched PRs"], [
    "Watched PRs",
    3,
    "2 open · 1 queued · 1 to review",
    "info",
  ]);
  assert.deepEqual(kpis.Failing, [
    "Failing",
    1,
    "PRs with red checks",
    "danger",
  ]);
  assert.deepEqual(kpis["Flaky checks"], [
    "Flaky checks",
    1,
    "top: e2e ×3",
    "warning",
  ]);
  assert.deepEqual(kpis.Pace, ["Pace", "15s", "fast · panel open", "info"]);
  // Open first, newest first; closed last.
  assert.deepEqual(columns.PR, ["acme/web#12", "acme/api#7", "acme/web#3"]);
  assert.deepEqual(columns.Title, ["fix: lint", "feat: thing", "old"]);
  assert.deepEqual(columns.Status, ["✗ 1 failing", "• queued #2", "✓ merged"]);
  assert.deepEqual(columns.Checks, [
    "5 ok · 1 red · 0 running",
    "8 ok · 0 red · 0 running",
    "4 ok · 0 red · 0 running",
  ]);
});

test("toOpenUILang keeps tricky titles intact through a round trip", () => {
  const titles = [
    'fix: handle "quoted" names',
    String.raw`chore: C:\path\to\thing\ and a trailing \\`,
    "feat: two\nlines\r\nand a\ttab",
    "it's # not // a comment, [really] (no) = + :",
    "",
  ];
  const watches = titles.map((title, i) => ({
    key: `o/r#${i}`,
    repo: "o/r",
    number: i,
    title,
    addedAt: titles.length - i,
  }));
  const dsl = toOpenUILang({ watches });
  const { columns } = parts(dsl);
  assert.deepEqual(
    columns.Title,
    titles.map((t) => t.replaceAll("\r\n", "\n")),
  );
  // Every value sits on one line of the document: newlines are escaped.
  assert.ok(!dsl.includes("two\nlines"));
});

test("toOpenUILang survives odd watch records", () => {
  const dsl = toOpenUILang({
    watches: [
      null,
      "nope",
      { key: "k1" },
      { repo: "o/r", number: 5, lastError: "boom", counts: { pass: "x" } },
      { repo: "o/r", number: 6, counts: { pass: 1, fail: 0, pending: 2 } },
      { repo: "o/r", number: 8, conflicting: true, counts: { pass: 1 } },
      { repo: "o/r", number: 9, closed: true, prState: "CLOSED" },
    ],
    pace: { intervalSeconds: Number.NaN },
    version: 2,
  });
  const { header, columns } = parts(dsl);
  assert.equal(header.args[1], "v2");
  assert.deepEqual(columns.PR, ["k1", "o/r#5", "o/r#6", "o/r#8", "o/r#9"]);
  assert.deepEqual(columns.Status, [
    "• not read yet",
    "✗ unreadable",
    "• running",
    "✗ conflict",
    "closed",
  ]);
  assert.equal(columns.Checks[1], "0 ok · 0 red · 0 running");
});

test("toOpenUILang output compiles to HTML with the titles escaped", () => {
  const html = compileToHtml(
    toOpenUILang({
      watches: [{ repo: "o/r", number: 1, title: "<script>alert(1)</script>" }],
    }),
  );
  assert.ok(!html.includes("<script>alert(1)"));
  assert.match(html, /&lt;script&gt;alert\(1\)&lt;\/script&gt;/);
});

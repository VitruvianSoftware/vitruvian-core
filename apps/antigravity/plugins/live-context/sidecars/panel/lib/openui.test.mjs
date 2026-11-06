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
  settings: {
    mode: "enforce",
    injectContract: true,
    injectGit: true,
    injectGitHub: true,
  },
  snapshot: {
    git: {
      branch: "feat/live-context",
      headSha: "1a2b3c4",
      dirtyCount: 2,
    },
    github: {
      openPrs: [{ number: 101, title: "feat: add plugin" }],
      mergedPrs: [{ number: 99, title: "chore: prep" }],
    },
  },
  verdicts: [
    {
      conversationId: "conv-1",
      mode: "enforce",
      chars: 640,
      verdict: "pass",
    },
    {
      conversationId: "conv-2",
      mode: "enforce",
      chars: 512,
      verdict: "block",
    },
  ],
};

test("parseOpenUILang resolves bindings and forward references", () => {
  const parsed = parseOpenUILang(`
    root = Card([hdr])
    hdr = Header("Live Context", "v0.1.0", "enforce", "info")
  `);
  assert.deepEqual(parsed.order, ["root", "hdr"]);
  assert.equal(parsed.root.$component, "Card");
});

test("resolveDataPath and compileToHtml work on live-context OpenUI documents", () => {
  assert.equal(resolveDataPath({ a: { b: 42 } }, "a.b"), 42);
  const html = compileToHtml(toOpenUILang(SAMPLE), { title: "Live Context" });
  assert.match(html, /^<!DOCTYPE html>/);
  assert.match(html, /feat\/live-context/);
  assert.equal(escapeHtml("<x>"), "&lt;x&gt;");
  assert.equal(openuiLiteral(true), "true");
});

test("toOpenUILang gives a valid, zeroed document for an empty state", () => {
  for (const state of [undefined, null, {}]) {
    const dsl = toOpenUILang(state);
    const { header, grid, columns } = parts(dsl);
    assert.deepEqual(header, {
      $component: "Header",
      args: ["Live Context", "", "idle", "neutral"],
    });
    assert.equal(grid.args[0], 4);
    assert.deepEqual(columns, {
      Conversation: [],
      Mode: [],
      Chars: [],
      Verdict: [],
    });
  }
});

test("toOpenUILang summarises a populated live-context state", () => {
  const dsl = toOpenUILang(SAMPLE);
  assert.match(
    dsl,
    /^# live-context state as OpenUI Lang v0\.5\nroot = Card\(\[/,
  );
  const { header, grid, columns } = parts(dsl);
  assert.deepEqual(header.args, [
    "Live Context",
    "v0.1.0",
    "enforce",
    "warning",
  ]);
  const kpis = Object.fromEntries(grid.args[1].map((k) => [k.args[0], k.args]));
  assert.deepEqual(kpis["Git Branch"], [
    "Git Branch",
    "feat/live-context",
    "2 dirty files",
    "warning",
  ]);
  assert.deepEqual(kpis["Open PRs"], [
    "Open PRs",
    1,
    "1 recently merged",
    "info",
  ]);
  assert.deepEqual(kpis["Contract Mode"], [
    "Contract Mode",
    "enforce",
    "injected each turn",
    "info",
  ]);
  assert.deepEqual(kpis["Stop Verdicts"], [
    "Stop Verdicts",
    2,
    "1 pass · 1 bounce",
    "warning",
  ]);
  assert.deepEqual(columns.Conversation, ["conv-1", "conv-2"]);
  assert.deepEqual(columns.Verdict, ["✓ pass", "✗ fail (filler)"]);
});

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
  FLAKE_WINDOW_MS,
  flakeCount,
  listFlaky,
  recordFlakes,
  spotFlakes,
  tagFlaky,
} from "./flakes.mjs";

const snap = (headSha, checks) => ({
  headSha,
  checks: Object.entries(checks).map(([name, bucket]) => ({ name, bucket })),
});

test("a check that fails and then passes on the same commit is a flake", () => {
  const first = spotFlakes(null, snap("s1", { e2e: "fail", lint: "pass" }));
  assert.deepEqual(first.flaked, []);
  const rerun = spotFlakes(
    first.seen,
    snap("s1", { e2e: "pending", lint: "pass" }),
  );
  assert.deepEqual(rerun.flaked, []);
  const passed = spotFlakes(
    rerun.seen,
    snap("s1", { e2e: "pass", lint: "pass" }),
  );
  assert.deepEqual(passed.flaked, ["e2e"]);
  // Counted once, not on every later read.
  assert.deepEqual(
    spotFlakes(passed.seen, snap("s1", { e2e: "pass" })).flaked,
    [],
  );
});

test("a check fixed by a new commit is not a flake", () => {
  const first = spotFlakes(null, snap("s1", { e2e: "fail" }));
  const fixed = spotFlakes(first.seen, snap("s2", { e2e: "pass" }));
  assert.deepEqual(fixed.flaked, []);
});

test("it takes two sightings inside the window to be called flaky", () => {
  let table = recordFlakes({}, "O/R", ["e2e"], 1000);
  assert.equal(flakeCount(table, "o/r", "e2e", 2000), 0);
  table = recordFlakes(table, "o/r", ["e2e"], 3000);
  assert.equal(flakeCount(table, "o/r", "e2e", 4000), 2);
  assert.equal(flakeCount(table, "o/r", "lint", 4000), 0);
  assert.equal(flakeCount(table, "other/repo", "e2e", 4000), 0);
});

test("old sightings age out and are dropped from the table", () => {
  let table = recordFlakes({}, "o/r", ["e2e"], 0);
  table = recordFlakes(table, "o/r", ["e2e"], 1000);
  assert.equal(flakeCount(table, "o/r", "e2e", FLAKE_WINDOW_MS + 500), 0);
  table = recordFlakes(table, "o/r", ["lint"], FLAKE_WINDOW_MS + 2000);
  assert.deepEqual(Object.keys(table), ["o/r|lint"]);
});

test("tagFlaky marks only the known flaky checks, and listFlaky ranks them", () => {
  let table = {};
  for (const t of [1, 2, 3]) table = recordFlakes(table, "o/r", ["e2e"], t);
  for (const t of [4, 5]) table = recordFlakes(table, "o/r", ["a|b"], t);
  table = recordFlakes(table, "o/r", ["once"], 6);
  const tagged = tagFlaky(
    table,
    "o/r",
    [{ name: "e2e" }, { name: "lint" }],
    10,
  );
  assert.deepEqual(tagged, [{ name: "e2e", flaky: 3 }, { name: "lint" }]);
  assert.deepEqual(listFlaky(table, 10), [
    { repo: "o/r", name: "e2e", count: 3 },
    { repo: "o/r", name: "a|b", count: 2 },
  ]);
});

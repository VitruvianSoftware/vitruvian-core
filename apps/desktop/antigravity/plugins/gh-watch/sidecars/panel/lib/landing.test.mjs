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
  LANDING_QUIET_MS,
  LANDING_SETTLE_MS,
  LANDING_TIMEOUT_MS,
  decideProgress,
  isGreen,
  landingActive,
  progressLines,
  progressTitle,
  readyToMerge,
} from "./landing.mjs";

const c = (name, bucket) => ({
  name,
  bucket,
  url: `https://example.test/${name}`,
});
const pr = (state, headSha, checks, extra = {}) => ({
  state,
  headSha,
  base: "main",
  checks,
  queued: false,
  ...extra,
});
const kinds = (result) => result.events.map((e) => e.kind);
// Runs a sequence of reads and returns the events of the last one.
function follow(...steps) {
  let state = null;
  let last;
  for (const [snap, baseChecks, now] of steps) {
    last = decideProgress(state, snap, baseChecks ?? null, now ?? 0);
    state = last.state;
  }
  return last;
}

test("isGreen needs every check finished, none failed, at least one passed", () => {
  assert.equal(
    isGreen(pr("OPEN", "s", [c("a", "pass"), c("b", "skip")])),
    true,
  );
  assert.equal(
    isGreen(pr("OPEN", "s", [c("a", "pass"), c("b", "pending")])),
    false,
  );
  assert.equal(
    isGreen(pr("OPEN", "s", [c("a", "pass"), c("b", "fail")])),
    false,
  );
  assert.equal(
    isGreen(pr("OPEN", "s", [c("a", "pass"), c("b", "cancel")])),
    true,
  );
  // Cancelled alone is not green: nothing passed.
  assert.equal(isGreen(pr("OPEN", "s", [c("a", "cancel")])), false);
  assert.equal(isGreen(pr("OPEN", "s", [c("a", "skip")])), false);
  assert.equal(isGreen(pr("OPEN", "s", [])), false);
  assert.equal(isGreen(pr("MERGED", "s", [c("a", "pass")])), false);
});

test("going green is announced once per commit", () => {
  const running = pr("OPEN", "s1", [c("a", "pending")]);
  const green = pr("OPEN", "s1", [c("a", "pass")]);
  assert.deepEqual(kinds(follow([running], [green])), ["green"]);
  assert.deepEqual(kinds(follow([running], [green], [green])), []);
  const green2 = pr("OPEN", "s2", [c("a", "pass")]);
  assert.deepEqual(
    kinds(
      follow(
        [running],
        [green],
        [pr("OPEN", "s2", [c("a", "pending")])],
        [green2],
      ),
    ),
    ["green"],
  );
});

test("a pull request that is already green when first seen is not announced", () => {
  const green = pr("OPEN", "s1", [c("a", "pass")]);
  assert.deepEqual(kinds(follow([green])), []);
  assert.deepEqual(kinds(follow([green], [green])), []);
});

test("a re-run on the same commit that goes green again is announced again", () => {
  const running = pr("OPEN", "s1", [c("a", "pending")]);
  const green = pr("OPEN", "s1", [c("a", "pass")]);
  const failed = pr("OPEN", "s1", [c("a", "fail")]);
  assert.deepEqual(kinds(follow([running], [green], [running], [green])), [
    "green",
  ]);
  assert.deepEqual(
    kinds(follow([running], [green], [failed], [running], [green])),
    ["green"],
  );
  // Staying green across reads is still news only once.
  assert.deepEqual(kinds(follow([running], [green], [green])), []);
});

test("leaving the merge queue without merging is announced", () => {
  const open = pr("OPEN", "s1", [c("a", "pass")]);
  const queued = { ...open, queued: true };
  assert.deepEqual(kinds(follow([open], [queued])), []);
  assert.deepEqual(kinds(follow([open], [queued], [open])), ["dequeued"]);
});

test("merged, then landed cleanly once the base branch's checks pass", () => {
  const open = pr("OPEN", "s1", [c("a", "pass")]);
  const merged = pr("MERGED", "s1", []);
  const first = follow([open], [merged, null, 1000]);
  assert.deepEqual(kinds(first), ["merged"]);
  assert.equal(landingActive({ progress: first.state }), true);

  const waiting = follow(
    [open],
    [merged, null, 1000],
    [merged, [c("build", "pending")], 2000],
  );
  assert.deepEqual(kinds(waiting), []);
  const landed = follow(
    [open],
    [merged, null, 1000],
    [merged, [c("build", "pending")], 2000],
    [merged, [c("build", "pass"), c("docs", "skip")], 1000 + LANDING_SETTLE_MS],
  );
  assert.deepEqual(kinds(landed), ["landed"]);
  assert.equal(landed.state.landing.result, "healthy");
  assert.equal(landingActive({ progress: landed.state }), false);
});

test("a failure on the base branch is reported at once, and only once", () => {
  const open = pr("OPEN", "s1", [c("a", "pass")]);
  const merged = pr("MERGED", "s1", []);
  const base = [c("build", "fail"), c("docs", "pending")];
  const failing = follow([open], [merged, null, 1000], [merged, base, 2000]);
  assert.deepEqual(kinds(failing), ["base-failing"]);
  assert.deepEqual(
    failing.events[0].failing.map((x) => x.name),
    ["build"],
  );
  assert.deepEqual(
    kinds(
      follow(
        [open],
        [merged, null, 1000],
        [merged, base, 2000],
        [merged, base, 3000],
      ),
    ),
    [],
  );
  // If the failing check is re-run and passes, the base branch recovers to healthy.
  const recovered = follow(
    [open],
    [merged, null, 1000],
    [merged, base, 2000],
    [merged, [c("build", "pass"), c("docs", "pass")], 1000 + LANDING_SETTLE_MS],
  );
  assert.deepEqual(kinds(recovered), ["landed"]);
  assert.equal(recovered.state.landing.result, "healthy");
  assert.equal(landingActive({ progress: recovered.state }), false);
});

test("watching the base branch gives up quietly", () => {
  const open = pr("OPEN", "s1", [c("a", "pass")]);
  const merged = pr("MERGED", "s1", []);
  const none = follow(
    [open],
    [merged, null, 0],
    [merged, [], LANDING_QUIET_MS],
  );
  assert.deepEqual(kinds(none), []);
  assert.equal(none.state.landing.result, "none");
  const slow = follow(
    [open],
    [merged, null, 0],
    [merged, [c("build", "pending")], LANDING_TIMEOUT_MS],
  );
  assert.deepEqual(kinds(slow), []);
  assert.equal(slow.state.landing.result, "unknown");
});

test("closed without merging is announced once; old news is not", () => {
  const open = pr("OPEN", "s1", [c("a", "pass")]);
  const closed = pr("CLOSED", "s1", []);
  assert.deepEqual(kinds(follow([open], [closed])), ["closed"]);
  assert.deepEqual(kinds(follow([open], [closed], [closed])), []);
  assert.deepEqual(kinds(follow([closed])), []);
  const merged = pr("MERGED", "s1", []);
  const late = follow([merged, [c("build", "pass")], 1000]);
  assert.deepEqual(kinds(late), []);
  assert.equal(landingActive({ progress: late.state }), false);
});

test("a reopened pull request starts over", () => {
  const open = pr("OPEN", "s1", [c("a", "pending")]);
  const closed = pr("CLOSED", "s1", []);
  const green = pr("OPEN", "s1", [c("a", "pass")]);
  assert.deepEqual(kinds(follow([open], [closed], [open], [green])), ["green"]);
});

test("the wording names the base branch and the failing checks", () => {
  const snap = { ...pr("MERGED", "abcdef0123456789", []), base: "main" };
  const text = progressLines(snap, [
    { kind: "merged" },
    { kind: "base-failing", failing: [c("build", "fail")] },
  ]).join("\n");
  assert.match(text, /merged into `main`/);
  assert.match(text, /- build https:\/\/example\.test\/build/);
  assert.match(text, /do not push to `main` directly/);
  assert.equal(
    progressTitle([{ kind: "green" }, { kind: "merged" }]),
    "checks passed, merged",
  );
});

test("passed checks seen right at the merge are not yet believed", () => {
  const open = pr("OPEN", "s1", [c("a", "pass")]);
  const merged = pr("MERGED", "s1", []);
  const queueOnly = [c("merge-queue-build", "pass")];
  const early = follow([open], [merged, null, 0], [merged, queueOnly, 30_000]);
  assert.deepEqual(kinds(early), []);
  assert.equal(landingActive({ progress: early.state }), true);
  // A failure, though, is reported straight away.
  const failing = follow(
    [open],
    [merged, null, 0],
    [merged, [c("x", "fail")], 30_000],
  );
  assert.deepEqual(kinds(failing), ["base-failing"]);
});

test("ready to merge means green, clean, and nothing set to merge it", () => {
  const green = { ...pr("OPEN", "s", [c("a", "pass")]), mergeState: "CLEAN" };
  assert.equal(readyToMerge(green), true);
  assert.equal(readyToMerge({ ...green, mergeState: "HAS_HOOKS" }), true);
  assert.equal(readyToMerge({ ...green, autoMerge: true }), false);
  assert.equal(readyToMerge({ ...green, queued: true }), false);
  assert.equal(readyToMerge({ ...green, isDraft: true }), false);
  assert.equal(readyToMerge({ ...green, mergeState: "BLOCKED" }), false);
  assert.equal(readyToMerge({ ...green, checks: [c("a", "pending")] }), false);
});

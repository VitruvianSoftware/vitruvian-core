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
  bucketOf,
  countChecks,
  decide,
  emptyState,
  failingLines,
  normaliseChecks,
  wakeMessage,
} from "./decide.mjs";

const run = (name, status, conclusion, workflowName = "CI") => ({
  __typename: "CheckRun",
  name,
  status,
  conclusion,
  workflowName,
  detailsUrl: `https://example.test/${name}`,
});
const snap = (headSha, ...raw) => ({ headSha, checks: normaliseChecks(raw) });
const names = (result) => result.wake.map((c) => c.name);

test("bucketOf maps check runs and status contexts", () => {
  assert.equal(bucketOf(run("a", "IN_PROGRESS", null)), "pending");
  assert.equal(bucketOf(run("a", "COMPLETED", "SUCCESS")), "pass");
  assert.equal(bucketOf(run("a", "COMPLETED", "FAILURE")), "fail");
  assert.equal(bucketOf(run("a", "COMPLETED", "TIMED_OUT")), "fail");
  assert.equal(bucketOf(run("a", "COMPLETED", "SKIPPED")), "skip");
  assert.equal(bucketOf(run("a", "COMPLETED", "CANCELLED")), "cancel");
  assert.equal(
    bucketOf({ __typename: "StatusContext", context: "x", state: "ERROR" }),
    "fail",
  );
  assert.equal(
    bucketOf({ __typename: "StatusContext", context: "x", state: "PENDING" }),
    "pending",
  );
});

test("normaliseChecks keeps the worst result for a repeated name", () => {
  const checks = normaliseChecks([
    run("lint", "COMPLETED", "SUCCESS"),
    run("lint", "COMPLETED", "FAILURE"),
  ]);
  assert.equal(checks.length, 1);
  assert.equal(checks[0].bucket, "fail");
  assert.deepEqual(countChecks(checks), {
    pass: 0,
    fail: 1,
    pending: 0,
    skip: 0,
    cancel: 0,
  });
});

test("a new failure wakes once, then stays quiet for the same commit", () => {
  const s = snap(
    "sha1",
    run("lint", "COMPLETED", "FAILURE"),
    run("test", "COMPLETED", "SUCCESS"),
  );
  const first = decide(emptyState(), s, 1000);
  assert.deepEqual(names(first), ["lint"]);
  const second = decide(first.state, s, 2000);
  assert.deepEqual(names(second), []);
});

test("a second, different failure on the same commit wakes for that one only", () => {
  const first = decide(
    emptyState(),
    snap("sha1", run("lint", "COMPLETED", "FAILURE")),
    1000,
  );
  const second = decide(
    first.state,
    snap(
      "sha1",
      run("lint", "COMPLETED", "FAILURE"),
      run("test", "COMPLETED", "FAILURE"),
    ),
    2000,
  );
  assert.deepEqual(names(second), ["test"]);
});

test("a new commit resets what was already reported", () => {
  const first = decide(
    emptyState(),
    snap("sha1", run("lint", "COMPLETED", "FAILURE")),
    1000,
  );
  const second = decide(
    first.state,
    snap("sha2", run("lint", "COMPLETED", "FAILURE")),
    2000,
  );
  assert.deepEqual(names(second), ["lint"]);
});

test("a re-run that passes and then fails again is reported again", () => {
  const first = decide(
    emptyState(),
    snap("sha1", run("lint", "COMPLETED", "FAILURE")),
    1000,
  );
  const rerun = decide(
    first.state,
    snap("sha1", run("lint", "IN_PROGRESS", null)),
    2000,
  );
  assert.deepEqual(names(rerun), []);
  const passed = decide(
    rerun.state,
    snap("sha1", run("lint", "COMPLETED", "SUCCESS")),
    3000,
  );
  const failed = decide(
    passed.state,
    snap("sha1", run("lint", "COMPLETED", "FAILURE")),
    4000,
  );
  assert.deepEqual(names(failed), ["lint"]);
});

test("a re-run that is still pending does not re-report the old failure", () => {
  const first = decide(
    emptyState(),
    snap("sha1", run("lint", "COMPLETED", "FAILURE")),
    1000,
  );
  const rerun = decide(
    first.state,
    snap("sha1", run("lint", "IN_PROGRESS", null)),
    2000,
  );
  const failed = decide(
    rerun.state,
    snap("sha1", run("lint", "COMPLETED", "FAILURE")),
    3000,
  );
  assert.deepEqual(names(failed), []);
});

test("waits while siblings in the same workflow are still running", () => {
  const running = snap(
    "sha1",
    run("lint", "COMPLETED", "FAILURE"),
    run("test", "IN_PROGRESS", null),
  );
  const held = decide(emptyState(), running, 1000, { holdMs: 60_000 });
  assert.deepEqual(names(held), []);
  assert.deepEqual(held.state.held, { since: 1000 });

  const done = snap(
    "sha1",
    run("lint", "COMPLETED", "FAILURE"),
    run("test", "COMPLETED", "FAILURE"),
  );
  const woke = decide(held.state, done, 20_000, { holdMs: 60_000 });
  assert.deepEqual(names(woke).sort(), ["lint", "test"]);
});

test("stops waiting once the hold time is up", () => {
  const running = snap(
    "sha1",
    run("lint", "COMPLETED", "FAILURE"),
    run("test", "IN_PROGRESS", null),
  );
  const held = decide(emptyState(), running, 1000, { holdMs: 60_000 });
  const woke = decide(held.state, running, 61_000, { holdMs: 60_000 });
  assert.deepEqual(names(woke), ["lint"]);
});

test("does not wait for a different workflow or for checks awaiting approval", () => {
  const other = snap(
    "sha1",
    run("lint", "COMPLETED", "FAILURE", "CI"),
    run("deploy", "IN_PROGRESS", null, "Deploy"),
  );
  assert.deepEqual(names(decide(emptyState(), other, 1000)), ["lint"]);
  const waiting = snap(
    "sha1",
    run("lint", "COMPLETED", "FAILURE"),
    run("gate", "WAITING", null),
  );
  assert.deepEqual(names(decide(emptyState(), waiting, 1000)), ["lint"]);
});

test("wakeMessage names the PR, the commit and each failing check", () => {
  const pr = {
    repo: "o/r",
    number: 7,
    title: "Add thing",
    url: "https://github.com/o/r/pull/7",
    branch: "feat/x",
    headSha: "abcdef0123456789",
  };
  const text = wakeMessage(
    pr,
    normaliseChecks([run("lint", "COMPLETED", "FAILURE")]),
  );
  assert.match(text, /o\/r#7/);
  assert.match(text, /abcdef012345/);
  assert.match(text, /- lint \[CI\] https:\/\/example\.test\/lint/);
  assert.match(text, /gh-watch plugin/);
});

const timed = (name, status, conclusion, startedAt, workflowName = "CI") => ({
  ...run(name, status, conclusion, workflowName),
  startedAt,
});

test("normaliseChecks lets a newer re-run supersede an older failure", () => {
  const older = timed("lint", "COMPLETED", "FAILURE", "2026-10-22T10:00:00Z");
  const pending = timed("lint", "IN_PROGRESS", null, "2026-10-22T10:05:00Z");
  const passed = timed("lint", "COMPLETED", "SUCCESS", "2026-10-22T10:05:00Z");
  assert.deepEqual(normaliseChecks([older, pending]), [
    {
      name: "lint",
      bucket: "pending",
      workflow: "CI",
      url: "https://example.test/lint",
      waiting: false,
    },
  ]);
  assert.equal(normaliseChecks([older, passed])[0].bucket, "pass");
  // Order in the rollup does not matter.
  assert.equal(normaliseChecks([passed, older])[0].bucket, "pass");
  // A newer failure still beats an older pass.
  const newerFail = timed(
    "lint",
    "COMPLETED",
    "FAILURE",
    "2026-10-22T11:00:00Z",
  );
  assert.equal(normaliseChecks([passed, newerFail])[0].bucket, "fail");
});

test("normaliseChecks falls back to the worst bucket without comparable times", () => {
  const fail = timed("lint", "COMPLETED", "FAILURE", "2026-10-22T10:00:00Z");
  // No time on the re-run.
  assert.equal(
    normaliseChecks([fail, run("lint", "COMPLETED", "SUCCESS")])[0].bucket,
    "fail",
  );
  // Same time (matrix legs started together).
  assert.equal(
    normaliseChecks([
      fail,
      timed("lint", "COMPLETED", "SUCCESS", "2026-10-22T10:00:00Z"),
    ])[0].bucket,
    "fail",
  );
  // A different workflow with the same check name.
  assert.equal(
    normaliseChecks([
      fail,
      timed("lint", "COMPLETED", "SUCCESS", "2026-10-22T11:00:00Z", "Other"),
    ])[0].bucket,
    "fail",
  );
  // completedAt is used when startedAt is missing.
  const done = {
    ...run("lint", "COMPLETED", "SUCCESS"),
    completedAt: "2026-10-22T12:00:00Z",
  };
  assert.equal(normaliseChecks([fail, done])[0].bucket, "pass");
});

test("failingLines quotes a log excerpt under its check", () => {
  const lines = failingLines([
    {
      name: "lint",
      workflow: "CI",
      url: "https://example.test/lint",
      excerpt: "\nerror: unused variable\n  at foo.ts:3\n",
    },
    { name: "test", excerpt: "   " },
    { name: "build" },
  ]);
  assert.deepEqual(lines, [
    "Newly failing checks (3):",
    "- lint [CI] https://example.test/lint",
    "  | error: unused variable",
    "  |   at foo.ts:3",
    "- test",
    "- build",
  ]);
});

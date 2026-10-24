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
  countChecks,
  fmtSize,
  isRemovable,
  judgeCleanup,
  summariseWorktrees,
  totalCacheKb,
} from "./core.mjs";

test("fmtSize formats KB, MB, GB and unknown values", () => {
  assert.equal(fmtSize(null), "…");
  assert.equal(fmtSize(undefined), "…");
  assert.equal(fmtSize(Number.NaN), "…");
  assert.equal(fmtSize(0), "0 KB");
  assert.equal(fmtSize(512), "512 KB");
  assert.equal(fmtSize(1024), "1 MB");
  assert.equal(fmtSize(256 * 1024), "256 MB");
  assert.equal(fmtSize(1024 * 1024), "1.0 GB");
  assert.equal(fmtSize(2.5 * 1024 * 1024), "2.5 GB");
});

test("countChecks tallies check runs and commit statuses accurately", () => {
  assert.deepEqual(countChecks([]), {
    passed: 0,
    failed: 0,
    running: 0,
    total: 0,
  });
  assert.deepEqual(countChecks(null), {
    passed: 0,
    failed: 0,
    running: 0,
    total: 0,
  });

  const rollup = [
    { status: "COMPLETED", conclusion: "SUCCESS" },
    { status: "COMPLETED", conclusion: "SKIPPED" },
    { status: "COMPLETED", conclusion: "NEUTRAL" },
    { status: "IN_PROGRESS", conclusion: null },
    { status: "QUEUED", conclusion: null },
    { status: "COMPLETED", conclusion: "FAILURE" },
    { state: "SUCCESS" },
    { state: "PENDING" },
    { state: "ERROR" },
  ];
  assert.deepEqual(countChecks(rollup), {
    passed: 4,
    failed: 2,
    running: 3,
    total: 9,
  });
});

test("isRemovable guards shared Bazel roots, cache/install dirs, and outside-home paths", () => {
  const home = "/Users/alice";
  const shared = [
    "/Users/alice/Library/Caches/bazel/_bazel_alice",
    "/Users/alice/.cache/bazel/_bazel_alice",
  ];

  // Valid isolated worktree output bases
  assert.equal(
    isRemovable(
      "/Users/alice/Library/Caches/bazel/_bazel_alice/0123456789abcdef0123456789abcdef",
      home,
      shared,
    ),
    true,
  );
  assert.equal(
    isRemovable(
      "/Users/alice/.cache/bazel/_bazel_alice/worktree-feat-x",
      home,
      shared,
    ),
    true,
  );

  // Refused: shared root itself, cache/install, traversal, outside home, non-bazel
  assert.equal(isRemovable(shared[0], home, shared), false);
  assert.equal(isRemovable(`${shared[0]}/cache`, home, shared), false);
  assert.equal(isRemovable(`${shared[0]}/install`, home, shared), false);
  assert.equal(
    isRemovable(`${shared[0]}/../_bazel_alice/hash`, home, shared),
    false,
  );
  assert.equal(
    isRemovable("/tmp/bazel/_bazel_alice/hash", home, shared),
    false,
  );
  assert.equal(
    isRemovable("/Users/alice/Workspace/project/sub/dir", home, shared),
    false,
  );
  assert.equal(isRemovable("/Users/alice/bazel/short", home, shared), false);
});

test("judgeCleanup requires merged PR into default branch, linked worktree, clean status, and matching HEAD", () => {
  const place = {
    root: "/ws/worktrees/feat-a",
    mainRoot: "/ws/main",
    isLinked: true,
    branch: "feat-a",
    head: "sha-123",
    defaultBranch: "main",
  };
  const mergedPr = {
    number: 42,
    state: "MERGED",
    base: "main",
    head: "sha-123",
  };

  // Ready when all checks pass
  assert.deepEqual(
    judgeCleanup(place, mergedPr, { ok: true, out: "" }, "ask"),
    { cleanup: "ready", note: "" },
  );

  // Mode off
  assert.deepEqual(
    judgeCleanup(place, mergedPr, { ok: true, out: "" }, "off"),
    { cleanup: "none", note: "" },
  );

  // Open PR
  assert.deepEqual(
    judgeCleanup(
      place,
      { ...mergedPr, state: "OPEN" },
      { ok: true, out: "" },
      "ask",
    ),
    { cleanup: "none", note: "" },
  );

  // Merged into non-default branch
  assert.deepEqual(
    judgeCleanup(
      place,
      { ...mergedPr, base: "release-1.0" },
      { ok: true, out: "" },
      "ask",
    ),
    { cleanup: "none", note: "merged into release-1.0, not main" },
  );

  // Main checkout
  assert.deepEqual(
    judgeCleanup(
      { ...place, isLinked: false },
      mergedPr,
      { ok: true, out: "" },
      "ask",
    ),
    { cleanup: "none", note: "main checkout: nothing to remove" },
  );

  // git status failed
  assert.deepEqual(
    judgeCleanup(place, mergedPr, { ok: false, out: "" }, "ask"),
    { cleanup: "blocked", note: "git status failed" },
  );

  // Dirty working tree
  assert.deepEqual(
    judgeCleanup(place, mergedPr, { ok: true, out: " M file.txt" }, "ask"),
    { cleanup: "blocked", note: "uncommitted changes" },
  );

  // Local commits ahead of PR head
  assert.deepEqual(
    judgeCleanup(
      { ...place, head: "sha-newer" },
      mergedPr,
      { ok: true, out: "" },
      "ask",
    ),
    {
      cleanup: "blocked",
      note: "local commits the pull request does not have",
    },
  );
});

test("totalCacheKb and summariseWorktrees aggregate disk usage and cleanup counts", () => {
  assert.equal(
    totalCacheKb([
      { path: "a", kb: 100 },
      { path: "b", kb: 200 },
    ]),
    300,
  );
  assert.equal(
    totalCacheKb([
      { path: "a", kb: 100 },
      { path: "b", kb: null },
    ]),
    null,
  );

  const summary = summariseWorktrees([
    {
      root: "/ws/wt-open",
      branch: "feat-open",
      isLinked: true,
      pr: {
        number: 10,
        state: "OPEN",
        checks: { passed: 2, failed: 1, running: 0, total: 3 },
      },
      treeKb: 1024,
      caches: [{ path: "/cache/1", kb: 2048 }],
      cleanup: "none",
    },
    {
      root: "/ws/wt-ready",
      branch: "feat-merged",
      isLinked: true,
      pr: {
        number: 11,
        state: "MERGED",
        checks: { passed: 4, failed: 0, running: 0, total: 4 },
      },
      treeKb: 4096,
      caches: [{ path: "/cache/2", kb: 8192 }],
      cleanup: "ready",
    },
    {
      root: "/ws/wt-done",
      branch: "feat-cleaned",
      isLinked: true,
      pr: { number: 9, state: "MERGED" },
      treeKb: 1024,
      caches: [],
      cleanup: "done",
    },
  ]);

  assert.equal(summary.total, 3);
  assert.equal(summary.linked, 3);
  assert.equal(summary.readyCount, 1);
  assert.equal(summary.cleanedCount, 1);
  assert.equal(summary.failingPrs, 1);
  assert.equal(summary.mergedPrs, 2);
  assert.equal(summary.totalTreeKb, 1024 + 4096);
  assert.equal(summary.totalBazelKb, 2048 + 8192);
  assert.equal(summary.reclaimableKb, 4096 + 8192);
  // Ready worktree sorts first, done worktree sorts last
  assert.deepEqual(
    summary.items.map((i) => i.branch),
    ["feat-merged", "feat-open", "feat-cleaned"],
  );
});

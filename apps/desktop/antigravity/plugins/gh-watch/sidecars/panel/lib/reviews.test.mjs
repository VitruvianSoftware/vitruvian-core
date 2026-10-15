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
  MAX_HIDDEN_REPOS,
  cleanRepoList,
  formatReviewTitle,
  reviewCheckStatus,
  reviewStatus,
  summariseReviews,
} from "./reviews.mjs";

const pr = (repo, number) => ({ repo, number, title: `t${number}` });
const ALL = [pr("acme/api", 1), pr("acme/web", 2), pr("acme/api", 3)];

test("with nothing switched off, every request is listed", () => {
  const out = summariseReviews(ALL);
  assert.equal(out.items.length, 3);
  assert.equal(out.total, 3);
  assert.equal(out.capped, false);
  assert.equal(out.singleRepo, false);
  assert.deepEqual(out.repos, [
    { repo: "acme/api", count: 2, shown: true },
    { repo: "acme/web", count: 1, shown: true },
  ]);
});

test("a switched-off repository is left out but still offered", () => {
  const out = summariseReviews(ALL, ["acme/api"]);
  assert.deepEqual(
    out.items.map((item) => item.number),
    [2],
  );
  assert.equal(out.total, 3);
  assert.equal(out.singleRepo, true);
  assert.deepEqual(out.repos, [
    { repo: "acme/api", count: 2, shown: false },
    { repo: "acme/web", count: 1, shown: true },
  ]);
});

test("a switched-off repository with no requests can still be switched on", () => {
  const out = summariseReviews(ALL, ["other/quiet"]);
  assert.deepEqual(out.repos.at(-1), {
    repo: "other/quiet",
    count: 0,
    shown: false,
  });
  assert.equal(out.items.length, 3);
});

test("repository names match whatever their case", () => {
  const out = summariseReviews(ALL, ["ACME/Api"]);
  assert.deepEqual(
    out.items.map((item) => item.number),
    [2],
  );
  // Listed once, under the name GitHub gave.
  assert.deepEqual(
    out.repos.map((row) => row.repo),
    ["acme/api", "acme/web"],
  );
});

test("a repository seen for the first time is shown", () => {
  const out = summariseReviews([...ALL, pr("new/repo", 9)], ["acme/api"]);
  assert.equal(out.repos.find((row) => row.repo === "new/repo").shown, true);
  assert.deepEqual(
    out.items.map((item) => item.number),
    [2, 9],
  );
});

test("reaching the read limit is reported", () => {
  assert.equal(summariseReviews(ALL, [], 3).capped, true);
  assert.equal(summariseReviews(ALL, [], 4).capped, false);
});

test("formatReviewTitle omits org/repo when only a single repo is selected", () => {
  const item = { repo: "acme/api", number: 42, title: "Fix race condition" };
  assert.equal(
    formatReviewTitle(item, false),
    "acme/api#42 Fix race condition",
  );
  assert.equal(formatReviewTitle(item, true), "#42 Fix race condition");
  assert.equal(formatReviewTitle(null, true), "");
});

test("reviewCheckStatus computes workflow and merge queue status accurately", () => {
  assert.deepEqual(
    reviewCheckStatus({
      queued: false,
      rollup: {
        state: "FAILURE",
        contexts: {
          checkRunCountsByState: [
            { state: "CANCELLED", count: 1 },
            { state: "SUCCESS", count: 14 },
          ],
          statusContextCountsByState: [],
        },
      },
    }),
    { text: "Passing", tone: "good" },
  );
  assert.deepEqual(
    reviewCheckStatus({
      queued: false,
      rollup: {
        state: "FAILURE",
        contexts: {
          checkRunCountsByState: [
            { state: "FAILURE", count: 2 },
            { state: "SUCCESS", count: 10 },
          ],
          statusContextCountsByState: [],
        },
      },
    }),
    { text: "2 failing", tone: "bad" },
  );
  assert.deepEqual(
    reviewCheckStatus({
      queued: true,
      queuePosition: 3,
      rollup: {
        state: "PENDING",
        contexts: {
          checkRunCountsByState: [{ state: "IN_PROGRESS", count: 4 }],
          statusContextCountsByState: [],
        },
      },
    }),
    { text: "In merge queue #3", tone: "run" },
  );
  assert.deepEqual(
    reviewCheckStatus({
      queued: false,
      rollup: {
        state: "PENDING",
        contexts: {
          checkRunCountsByState: [{ state: "IN_PROGRESS", count: 3 }],
          statusContextCountsByState: [{ state: "PENDING", count: 1 }],
        },
      },
    }),
    { text: "4 running", tone: "run" },
  );
  assert.deepEqual(
    reviewCheckStatus({
      queued: false,
      rollup: { state: "SUCCESS" },
    }),
    { text: "Passing", tone: "good" },
  );
  assert.equal(reviewCheckStatus({}), null);
  assert.equal(reviewCheckStatus(null), null);
});

test("cleanRepoList keeps only owner/name strings, once each", () => {
  assert.deepEqual(
    cleanRepoList([
      "acme/api",
      "ACME/API",
      "not a repo",
      "a/b/c",
      42,
      null,
      "acme/web",
    ]),
    ["acme/api", "acme/web"],
  );
  assert.deepEqual(cleanRepoList("acme/api"), []);
  assert.deepEqual(cleanRepoList(undefined), []);
});

test("cleanRepoList caps the list", () => {
  const many = Array.from(
    { length: MAX_HIDDEN_REPOS + 50 },
    (_, i) => `o/r${i}`,
  );
  assert.equal(cleanRepoList(many).length, MAX_HIDDEN_REPOS);
});

test("reviewStatus reflects reviewDecision when present", () => {
  assert.deepEqual(reviewStatus({ reviewDecision: "APPROVED" }), {
    text: "Approved",
    tone: "good",
  });
  assert.deepEqual(reviewStatus({ reviewDecision: "CHANGES_REQUESTED" }), {
    text: "Changes requested",
    tone: "bad",
  });
  assert.deepEqual(reviewStatus({ reviewDecision: "REVIEW_REQUIRED" }), {
    text: "Review required",
    tone: "wait",
  });
});

test("reviewStatus falls back to latestReviews and reviewRequests", () => {
  assert.deepEqual(
    reviewStatus({
      latestReviews: [{ state: "APPROVED" }],
    }),
    { text: "Approved", tone: "good" },
  );
  assert.deepEqual(
    reviewStatus({
      latestReviews: [{ state: "APPROVED" }, { state: "CHANGES_REQUESTED" }],
    }),
    { text: "Changes requested", tone: "bad" },
  );
  assert.deepEqual(
    reviewStatus({
      reviewRequests: [{ login: "octocat" }],
    }),
    { text: "Review requested", tone: "wait" },
  );
  assert.equal(reviewStatus({}), null);
  assert.equal(reviewStatus(null), null);
});

test("readyForAction is true only for a finished, all-green pipeline", async () => {
  const { readyForAction } = await import("./reviews.mjs");
  const rollup = (rows) => ({
    state: "SUCCESS",
    contexts: { checkRunCountsByState: rows },
  });
  const pass = { state: "SUCCESS", count: 3 };
  assert.equal(
    readyForAction({ mergeable: "MERGEABLE", rollup: rollup([pass]) }),
    true,
  );
  assert.equal(
    readyForAction({
      mergeable: "MERGEABLE",
      rollup: rollup([pass, { state: "SKIPPED", count: 2 }]),
    }),
    true,
  );
  assert.equal(
    readyForAction({
      rollup: rollup([pass, { state: "IN_PROGRESS", count: 1 }]),
    }),
    false,
  );
  assert.equal(
    readyForAction({
      mergeable: "MERGEABLE",
      rollup: rollup([pass, { state: "FAILURE", count: 1 }]),
    }),
    false,
  );
  assert.equal(
    readyForAction({
      rollup: rollup([pass, { state: "CANCELLED", count: 1 }]),
    }),
    false,
  );
  assert.equal(
    readyForAction({ mergeable: "MERGEABLE", rollup: rollup([]) }),
    false,
  );
  assert.equal(
    readyForAction({
      mergeable: "MERGEABLE",
      queued: true,
      rollup: rollup([pass]),
    }),
    false,
  );
  assert.equal(
    readyForAction({ mergeable: "CONFLICTING", rollup: rollup([pass]) }),
    false,
  );
  // Without per-state counts, only an overall SUCCESS counts.
  assert.equal(
    readyForAction({ mergeable: "MERGEABLE", rollup: { state: "SUCCESS" } }),
    true,
  );
  assert.equal(
    readyForAction({ mergeable: "MERGEABLE", rollup: { state: "PENDING" } }),
    false,
  );
  assert.equal(readyForAction({ mergeable: "MERGEABLE", rollup: null }), false);
  // Only a confirmed "no conflict" counts; GitHub's "unknown" does not.
  assert.equal(
    readyForAction({ mergeable: "UNKNOWN", rollup: rollup([pass]) }),
    false,
  );
  assert.equal(readyForAction({ rollup: rollup([pass]) }), false);
  assert.equal(readyForAction(null), false);
});

test("conflictBadge flags conflicts, and unknown until GitHub has checked", async () => {
  const { conflictBadge } = await import("./reviews.mjs");
  assert.deepEqual(conflictBadge("CONFLICTING"), {
    text: "Conflicts",
    tone: "bad",
  });
  assert.equal(conflictBadge("MERGEABLE"), null);
  assert.deepEqual(conflictBadge("UNKNOWN"), {
    text: "Checking for conflicts",
    tone: "wait",
  });
  assert.deepEqual(conflictBadge(undefined), {
    text: "Checking for conflicts",
    tone: "wait",
  });
});

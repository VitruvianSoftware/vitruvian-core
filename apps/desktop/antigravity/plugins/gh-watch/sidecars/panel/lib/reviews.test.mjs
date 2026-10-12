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

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
  fetchCommitChecks,
  fetchFailureLog,
  fetchMyPrs,
  fetchRepoPrs,
  fetchReviewRequests,
} from "./github.mjs";

// A stand-in for `gh` that records the search it was asked for and returns
// the given pull requests.
function fakeGh(nodes) {
  const asked = [];
  const run = async (args) => {
    const q = args.find((arg) => arg.startsWith("q="));
    asked.push(q?.slice(2));
    return JSON.stringify({ data: { search: { nodes } } });
  };
  return { run, asked };
}

const node = (number, extra = {}) => ({
  number,
  title: `t${number}`,
  url: `https://github.com/o/r/pull/${number}`,
  isDraft: false,
  repository: { nameWithOwner: "o/r" },
  author: { __typename: "User", login: "someone" },
  mergeable: "MERGEABLE",
  commits: {
    nodes: [
      {
        commit: {
          statusCheckRollup: {
            state: "SUCCESS",
            contexts: {
              checkRunCountsByState: [{ state: "SUCCESS", count: 2 }],
            },
          },
        },
      },
    ],
  },
  ...extra,
});

test("review requests leave drafts out; your own include them", async () => {
  const nodes = [node(1), node(2, { isDraft: true })];
  const reviews = fakeGh(nodes);
  assert.deepEqual(
    (await fetchReviewRequests(reviews.run)).map((pr) => pr.number),
    [1],
  );
  assert.deepEqual(reviews.asked, ["is:pr is:open review-requested:@me"]);

  const mine = fakeGh(nodes);
  const got = await fetchMyPrs(mine.run);
  assert.deepEqual(
    got.map((pr) => [pr.number, pr.isDraft, pr.ready]),
    [
      [1, false, true],
      // A draft is never offered for approval.
      [2, true, false],
    ],
  );
  assert.deepEqual(mine.asked, ["is:pr is:open author:@me archived:false"]);
});

test("all open pull requests are read only for the ticked repositories", async () => {
  const gh = fakeGh([node(5)]);
  await fetchRepoPrs(["o/r", "x/y", "not a repo"], gh.run);
  assert.deepEqual(gh.asked, [
    "is:pr is:open archived:false repo:o/r repo:x/y",
  ]);

  const none = fakeGh([node(5)]);
  assert.deepEqual(await fetchRepoPrs([], none.run), []);
  assert.deepEqual(none.asked, []);
});

test("each row carries its conflict badge", async () => {
  const gh = fakeGh([node(7, { mergeable: "CONFLICTING" })]);
  const [pr] = await fetchMyPrs(gh.run);
  assert.deepEqual(pr.conflict, { text: "Conflicts", tone: "bad" });
  assert.equal(pr.ready, false);
});

test("each row carries review decision and autoMerge state", async () => {
  const gh = fakeGh([
    node(8, {
      reviewDecision: "APPROVED",
      autoMergeRequest: { enabledAt: "2026-10-22T00:00:00Z" },
    }),
  ]);
  const [pr] = await fetchMyPrs(gh.run);
  assert.deepEqual(pr.review, { text: "Approved", tone: "good" });
  assert.equal(pr.autoMerge, true);
});

test("fetchCommitChecks paginates all check-run pages and deduplicates by newest id", async () => {
  const calls = [];
  const run = async (args) => {
    calls.push(args);
    return JSON.stringify([
      {
        check_runs: [
          {
            id: 10,
            name: "build",
            status: "COMPLETED",
            conclusion: "FAILURE",
            html_url: "https://github.com/o/r/actions/runs/1/job/10",
          },
          {
            id: 11,
            name: "Dependabot",
            status: "COMPLETED",
            conclusion: "FAILURE",
            app: { slug: "dependabot" },
          },
        ],
      },
      {
        check_runs: [
          {
            id: 20,
            name: "build",
            status: "COMPLETED",
            conclusion: "SUCCESS",
            html_url: "https://github.com/o/r/actions/runs/2/job/20",
          },
          {
            id: 21,
            name: "deploy",
            status: "IN_PROGRESS",
            conclusion: null,
            html_url: "https://github.com/o/r/actions/runs/2/job/21",
          },
        ],
      },
    ]);
  };
  const checks = await fetchCommitChecks("o/r", "sha123", run);
  assert.ok(calls[0].includes("--paginate"));
  assert.ok(calls[0].includes("--slurp"));
  assert.deepEqual(
    checks.map((c) => [c.name, c.bucket]),
    [
      ["build", "pass"],
      ["deploy", "pending"],
    ],
  );
});

test("fetchFailureLog scopes to --job when jobId is provided", async () => {
  const calls = [];
  const run = async (args) => {
    calls.push(args);
    return "log output";
  };
  await fetchFailureLog("o/r", 100, 200, run);
  await fetchFailureLog("o/r", 100, null, run);
  assert.deepEqual(calls, [
    ["run", "view", "100", "--job", "200", "--log-failed", "-R", "o/r"],
    ["run", "view", "100", "--log-failed", "-R", "o/r"],
  ]);
});

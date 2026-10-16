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

import { fetchMyPrs, fetchRepoPrs, fetchReviewRequests } from "./github.mjs";

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

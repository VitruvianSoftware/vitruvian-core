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

import { reviewAction } from "./actions.mjs";

const green = (extra = {}) => ({
  repo: "o/r",
  number: 5,
  state: "OPEN",
  isDraft: false,
  mergeable: "MERGEABLE",
  checks: [
    { name: "build", bucket: "pass" },
    { name: "lint", bucket: "skip" },
  ],
  ...extra,
});

function github(snap) {
  const calls = [];
  return {
    calls,
    fetchPr: async (repo, number) => {
      calls.push(["read", repo, number]);
      return snap;
    },
    approvePr: async (repo, number) => calls.push(["approve", repo, number]),
    setAutoMerge: async (repo, number, enabled, method) =>
      calls.push(["merge", repo, number, enabled, method]),
  };
}

test("approve only approves", async () => {
  const gh = github(green());
  assert.deepEqual(await reviewAction({ repo: "o/r", number: 5 }, gh), {
    approved: true,
    merge: false,
  });
  assert.deepEqual(gh.calls, [
    ["read", "o/r", 5],
    ["approve", "o/r", 5],
  ]);
});

test("approve and merge approves first, then turns on auto-merge", async () => {
  const gh = github(green());
  await reviewAction(
    { repo: "o/r", number: "5", merge: true, mergeMethod: "squash" },
    gh,
  );
  assert.deepEqual(gh.calls, [
    ["read", "o/r", 5],
    ["approve", "o/r", 5],
    ["merge", "o/r", 5, true, "squash"],
  ]);
});

test("nothing is approved or merged unless it is still green", async () => {
  const cases = [
    [green({ checks: [{ name: "b", bucket: "fail" }] }), /failing/],
    [
      green({
        checks: [
          { name: "b", bucket: "pass" },
          { name: "c", bucket: "pending" },
        ],
      }),
      /still running/,
    ],
    [green({ checks: [{ name: "b", bucket: "cancel" }] }), /cancelled/],
    [green({ checks: [] }), /No checks have passed/],
    [
      green({ checks: [{ name: "b", bucket: "skip" }] }),
      /No checks have passed/,
    ],
    [green({ mergeable: "CONFLICTING" }), /conflicts/],
    [green({ state: "MERGED" }), /no longer open/],
    [green({ isDraft: true }), /draft/],
  ];
  for (const [snap, why] of cases) {
    const gh = github(snap);
    await assert.rejects(
      reviewAction({ repo: "o/r", number: 5, merge: true }, gh),
      why,
    );
    assert.deepEqual(gh.calls, [["read", "o/r", 5]]);
  }
});

test("a bad repository or number is refused before anything is read", async () => {
  for (const input of [
    { repo: "o/r; rm -rf", number: 5 },
    { repo: "o", number: 5 },
    { repo: "o/r", number: 0 },
    { repo: "o/r", number: "5x" },
  ]) {
    const gh = github(green());
    await assert.rejects(reviewAction(input, gh), /not a pull request/);
    assert.deepEqual(gh.calls, []);
  }
});

test("a failed merge says the approval went through", async () => {
  const gh = github(green());
  gh.setAutoMerge = async () => {
    throw new Error("auto-merge is not allowed");
  };
  await assert.rejects(
    reviewAction({ repo: "o/r", number: 5, merge: true }, gh),
    /Approved, but could not set it to merge: auto-merge is not allowed/,
  );
});

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

// Approving, and approving then merging, a pull request from the "Waiting on
// your review" list. Kept apart from main.mjs, with GitHub passed in, so it
// runs under `node --test`.

import { notGreenReason } from "./reviews.mjs";

const REPO = /^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/;

// Approves `repo#number`, and with `merge` also turns on GitHub's auto-merge
// for it. Nothing happens unless a fresh read of the pull request shows it is
// still fully green: the list it was clicked in can be minutes old.
//
// Merging goes through GitHub's auto-merge, never around it. On a repository
// with a merge queue that adds the pull request to the queue; elsewhere GitHub
// merges it with `mergeMethod` once its required reviews are in. Branch
// protection and the queue's own checks still apply.
//
// Returns { approved: true, merge: boolean }. Throws with a message fit to
// show the user.
export async function reviewAction(
  { repo, number, merge = false, mergeMethod = "squash" },
  { fetchPr, approvePr, setAutoMerge },
) {
  const n = Number(number);
  if (
    typeof repo !== "string" ||
    !REPO.test(repo) ||
    !Number.isInteger(n) ||
    n < 1
  )
    throw new Error("That is not a pull request");
  const snap = await fetchPr(repo, n);
  const reason = notGreenReason(snap);
  if (reason) throw new Error(`Not done: ${reason}.`);
  await approvePr(repo, n);
  if (merge) {
    try {
      await setAutoMerge(repo, n, true, mergeMethod);
    } catch (err) {
      throw new Error(
        `Approved, but could not set it to merge: ${err.message}`,
        {
          cause: err,
        },
      );
    }
  }
  return { approved: true, merge: merge === true };
}

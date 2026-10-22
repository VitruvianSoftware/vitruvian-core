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

// The "Waiting on your review" list, as pure logic so it runs under
// `node --test`.
//
// The user chooses which repositories to list. What is saved is the ones they
// switched off, not the ones they left on, so a repository that asks for
// their review for the first time shows up instead of being silently hidden.

// How many review requests one read asks GitHub for. It is one page of the
// search API, so it still costs a single request.
export const REVIEW_LIMIT = 100;

export const MAX_HIDDEN_REPOS = 200;

const REPO = /^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/;

// Returns a clean list of "owner/name" strings: anything else is dropped,
// repeats are removed (GitHub ignores case in names) and the list is capped.
export function cleanRepoList(value) {
  if (!Array.isArray(value)) return [];
  const seen = new Set();
  const out = [];
  for (const entry of value) {
    if (typeof entry !== "string" || !REPO.test(entry)) continue;
    const key = entry.toLowerCase();
    if (seen.has(key)) continue;
    seen.add(key);
    out.push(entry);
    if (out.length >= MAX_HIDDEN_REPOS) break;
  }
  return out;
}

// Formats the pull request link text for the "Waiting on your review" list.
// When only a single repository is shown, omits the org/repo prefix so the
// line stays compact alongside the workflow status badge.
export function formatReviewTitle(pr, singleRepo = false) {
  if (!pr) return "";
  return singleRepo
    ? `#${pr.number} ${pr.title}`
    : `${pr.repo}#${pr.number} ${pr.title}`;
}

const FAIL_STATES = new Set([
  "FAILURE",
  "ERROR",
  "TIMED_OUT",
  "ACTION_REQUIRED",
  "STARTUP_FAILURE",
]);
const PENDING_STATES = new Set([
  "IN_PROGRESS",
  "QUEUED",
  "WAITING",
  "REQUESTED",
  "PENDING",
  "EXPECTED",
]);
const SKIP_STATES = new Set(["SKIPPED", "NEUTRAL", "STALE"]);

function rollupCounts(rollup) {
  const ctx = rollup?.contexts;
  const checkCounts = ctx?.checkRunCountsByState;
  const statusCounts = ctx?.statusContextCountsByState;
  if (!Array.isArray(checkCounts) && !Array.isArray(statusCounts)) return null;
  const counts = { pass: 0, fail: 0, pending: 0, skip: 0, cancel: 0 };
  for (const row of [...(checkCounts ?? []), ...(statusCounts ?? [])]) {
    const state = (row?.state ?? "").toUpperCase();
    const n = Number(row?.count ?? 0);
    if (!n) continue;
    if (state === "SUCCESS") counts.pass += n;
    else if (FAIL_STATES.has(state)) counts.fail += n;
    else if (PENDING_STATES.has(state)) counts.pending += n;
    else if (SKIP_STATES.has(state)) counts.skip += n;
    else if (state === "CANCELLED") counts.cancel += n;
  }
  return counts;
}

// Determines the CI / merge-queue status badge for a review-requested PR.
// Uses exact check/status counts when present so a cancelled old run does not
// masquerade as a failure.
export function reviewCheckStatus(pr) {
  if (!pr) return null;
  const place = pr.queuePosition ? ` #${pr.queuePosition}` : "";
  const counts = rollupCounts(pr.rollup);
  if (counts) {
    if (counts.fail > 0) return { text: `${counts.fail} failing`, tone: "bad" };
    if (pr.queued) return { text: `In merge queue${place}`, tone: "run" };
    if (counts.pending > 0)
      return { text: `${counts.pending} running`, tone: "run" };
    if (counts.pass > 0) return { text: "Passing", tone: "good" };
    return null;
  }
  const state = (pr.rollup?.state ?? "").toUpperCase();
  if (state === "FAILURE" || state === "ERROR")
    return { text: "Failing", tone: "bad" };
  if (pr.queued) return { text: `In merge queue${place}`, tone: "run" };
  if (state === "PENDING" || state === "EXPECTED")
    return { text: "Running", tone: "run" };
  if (state === "SUCCESS") return { text: "Passing", tone: "good" };
  return null;
}

// Whether a review request in the list is fully green, so the panel may offer
// to approve and merge it. Every check has finished and none failed, at least
// one passed, it is not already in a merge queue, and GitHub has confirmed it
// has no conflict. A cancelled check does not count against it, matching
// reviewCheckStatus. Anything less, or anything unknown, is not ready: the
// buttons only appear once the pipeline is green.
export function readyForAction(pr) {
  if (!pr || pr.queued || pr.isDraft) return false;
  if ((pr.mergeable ?? "").toUpperCase() !== "MERGEABLE") return false;
  const counts = rollupCounts(pr.rollup);
  if (counts)
    return counts.fail === 0 && counts.pending === 0 && counts.pass > 0;
  return (pr.rollup?.state ?? "").toUpperCase() === "SUCCESS";
}

// The badges every row of the three lists carries besides its CI status: the
// review state and whether auto-merge is armed. `pr` is anything with
// `reviewDecision` (and optionally `latestReviews`, `reviewRequests`, `state`)
// and `autoMerge`.
export function rowReviewFields(pr) {
  return {
    review: reviewStatus(pr ? { state: "OPEN", ...pr } : null),
    autoMerge: Boolean(pr?.autoMerge),
  };
}

// Lays the three lists the panel shows over the shared repository filter.
//
//   reviews  open pull requests waiting on the user's review
//   mine     open pull requests the user opened
//   all      every open pull request in the repositories that are switched on
//   watched  "owner/name" of each watched pull request
//   hidden   repositories the user switched off
//
// The tick boxes cover every repository seen in the first two lists or among
// the watched pull requests, plus any switched off; `all` is read for the
// switched-on ones, so it never adds a repository of its own. Each count is
// the number of distinct open pull requests in that repository across the
// lists.
export function summariseLists(
  { reviews = [], mine = [], all = [], watched = [] },
  hidden = [],
  limit = REVIEW_LIMIT,
) {
  const off = new Set(hidden.map((repo) => repo.toLowerCase()));
  const isOff = (repo) => off.has(repo.toLowerCase());
  const names = new Map(); // lower-case name -> name as GitHub gives it
  const seen = new Map(); // lower-case name -> Set of numbers
  const note = (repo, number) => {
    if (!repo) return;
    const key = repo.toLowerCase();
    if (!names.has(key)) names.set(key, repo);
    if (!seen.has(key)) seen.set(key, new Set());
    if (number) seen.get(key).add(number);
  };
  for (const pr of [...reviews, ...mine, ...all]) note(pr.repo, pr.number);
  for (const repo of watched) note(repo, null);
  for (const repo of hidden) note(repo, null);
  const repos = [...names.entries()]
    .map(([key, repo]) => ({
      repo,
      count: seen.get(key).size,
      shown: !isOff(repo),
    }))
    .sort((a, b) => a.repo.localeCompare(b.repo));
  const list = (items) => ({
    items: items.filter((pr) => !isOff(pr.repo)),
    total: items.length,
    capped: items.length >= limit,
  });
  return {
    repos,
    shownRepos: repos.filter((row) => row.shown).map((row) => row.repo),
    singleRepo: repos.filter((row) => row.shown).length === 1,
    reviews: list(reviews),
    mine: list(mine),
    all: list(all),
  };
}

// The same test, made again on a freshly read pull request just before the
// panel approves or merges it, since the list can be up to two minutes old.
// Returns null when it is still green, or the reason it is not.
export function notGreenReason(snap) {
  if (!snap) return "The pull request could not be read";
  if (snap.state !== "OPEN") return "The pull request is no longer open";
  if (snap.isDraft) return "The pull request is a draft";
  const mergeable = (snap.mergeable ?? "").toUpperCase();
  if (mergeable === "CONFLICTING")
    return "The pull request has merge conflicts";
  if (mergeable !== "MERGEABLE")
    return "GitHub has not finished checking it for conflicts; try again in a minute";
  const counts = { pass: 0, fail: 0, pending: 0, skip: 0, cancel: 0 };
  for (const check of snap.checks ?? []) counts[check.bucket] += 1;
  if (counts.fail > 0) return `${counts.fail} check(s) failing`;
  if (counts.pending > 0) return `${counts.pending} check(s) still running`;
  // Cancelled checks do not block on their own; with nothing passed this
  // still refuses.
  if (counts.pass === 0) return "No checks have passed yet";
  return null;
}

// A second badge for a review request, about conflicts rather than CI, since a
// pipeline can pass on a branch that no longer merges cleanly. GitHub works
// conflicts out lazily, so "unknown" usually settles by the next read.
// Returns null when GitHub reports no conflict.
export function conflictBadge(mergeable) {
  const state = (mergeable ?? "").toUpperCase();
  if (state === "CONFLICTING") return { text: "Conflicts", tone: "bad" };
  if (state === "MERGEABLE") return null;
  return { text: "Checking for conflicts", tone: "wait" };
}

// Determines the review status badge for a pull request snapshot.
// Returns null if there is no review activity or the pull request is no longer open.
export function reviewStatus(pr) {
  if (!pr) return null;
  if (pr.state && pr.state.toUpperCase() !== "OPEN") return null;
  const decision = (pr.reviewDecision ?? "").toUpperCase();
  if (decision === "APPROVED") return { text: "Approved", tone: "good" };
  if (decision === "CHANGES_REQUESTED")
    return { text: "Changes requested", tone: "bad" };
  if (decision === "REVIEW_REQUIRED")
    return { text: "Review required", tone: "wait" };

  // Fallback when reviewDecision is not populated (e.g. branches without required reviews)
  const reviews = pr.latestReviews ?? [];
  if (
    reviews.some((r) => (r.state ?? "").toUpperCase() === "CHANGES_REQUESTED")
  ) {
    return { text: "Changes requested", tone: "bad" };
  }
  if (reviews.some((r) => (r.state ?? "").toUpperCase() === "APPROVED")) {
    return { text: "Approved", tone: "good" };
  }
  if ((pr.reviewRequests ?? []).length > 0) {
    return { text: "Review requested", tone: "wait" };
  }
  return null;
}

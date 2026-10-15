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

// Splits what GitHub returned into what the panel shows.
//
//   items   the review requests in repositories that are switched on
//   repos   every repository the panel knows about, with how many requests
//           it has and whether it is switched on; hidden ones are kept even
//           at zero so they can be switched back on
//   total   how many requests there are before filtering
//   capped  true when GitHub may have more than were read
export function summariseReviews(all, hidden = [], limit = REVIEW_LIMIT) {
  const off = new Set(hidden.map((repo) => repo.toLowerCase()));
  const isOff = (repo) => off.has(repo.toLowerCase());
  const counts = new Map();
  for (const pr of all) counts.set(pr.repo, (counts.get(pr.repo) ?? 0) + 1);
  for (const repo of hidden) {
    const known = [...counts.keys()].some(
      (name) => name.toLowerCase() === repo.toLowerCase(),
    );
    if (!known) counts.set(repo, 0);
  }
  const repos = [...counts.entries()]
    .map(([repo, count]) => ({ repo, count, shown: !isOff(repo) }))
    .sort((a, b) => a.repo.localeCompare(b.repo));
  return {
    items: all.filter((pr) => !isOff(pr.repo)),
    repos,
    total: all.length,
    capped: all.length >= limit,
    singleRepo: repos.filter((row) => row.shown).length === 1,
  };
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
// to approve and merge it. Every check has finished and none failed or was
// cancelled, at least one passed, it is not already in a merge queue, and
// GitHub does not report a conflict. Anything less, or anything unknown, is
// not ready: the buttons only appear once the pipeline is green.
export function readyForAction(pr) {
  if (!pr || pr.queued || pr.isDraft) return false;
  if ((pr.mergeable ?? "").toUpperCase() === "CONFLICTING") return false;
  const counts = rollupCounts(pr.rollup);
  if (counts)
    return (
      counts.fail === 0 &&
      counts.pending === 0 &&
      counts.cancel === 0 &&
      counts.pass > 0
    );
  return (pr.rollup?.state ?? "").toUpperCase() === "SUCCESS";
}

// The same test, made again on a freshly read pull request just before the
// panel approves or merges it, since the list can be up to two minutes old.
// Returns null when it is still green, or the reason it is not.
export function notGreenReason(snap) {
  if (!snap) return "The pull request could not be read";
  if (snap.state !== "OPEN") return "The pull request is no longer open";
  if (snap.isDraft) return "The pull request is a draft";
  if ((snap.mergeable ?? "").toUpperCase() === "CONFLICTING")
    return "The pull request has merge conflicts";
  const counts = { pass: 0, fail: 0, pending: 0, skip: 0, cancel: 0 };
  for (const check of snap.checks ?? []) counts[check.bucket] += 1;
  if (counts.fail > 0) return `${counts.fail} check(s) failing`;
  if (counts.cancel > 0) return `${counts.cancel} check(s) cancelled`;
  if (counts.pending > 0) return `${counts.pending} check(s) still running`;
  if (counts.pass === 0) return "No checks have passed yet";
  return null;
}

// Determines the review status badge for a pull request snapshot.
// Returns null if there is no review activity.
export function reviewStatus(pr) {
  if (!pr) return null;
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

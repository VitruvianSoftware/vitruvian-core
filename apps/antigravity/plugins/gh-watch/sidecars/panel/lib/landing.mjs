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

// Following a change after its checks stop failing: green, queued, merged,
// and whether the base branch stayed healthy afterwards. Pure logic, like
// decide.mjs, so it runs under `node --test`.

// How long to keep watching the base branch after a merge before giving up.
export const LANDING_TIMEOUT_MS = 2 * 60 * 60 * 1000;
// With a merge queue, the merge commit already carries the queue's own
// passed checks at the moment of merging, before the base branch's workflows
// have started. "Landed" is only believed once this long has passed.
export const LANDING_SETTLE_MS = 90 * 1000;
// If nothing has started on the merge commit by then, nothing is going to.
export const LANDING_QUIET_MS = 10 * 60 * 1000;

// True when every check on the pull request has finished, none failed, and
// at least one passed. A cancelled check does not block: it is usually an old
// run superseded by a newer one, and GitHub does not treat it as failing.
export function isGreen(snap) {
  if (snap.state !== "OPEN" || snap.checks.length === 0) return false;
  let passed = 0;
  for (const check of snap.checks) {
    if (check.bucket === "fail" || check.bucket === "pending") return false;
    if (check.bucket === "pass") passed += 1;
  }
  return passed > 0;
}

// True when a pull request is green and mergeable but nothing is going to
// merge it: not queued and auto-merge not armed. It is waiting on a person.
// HAS_HOOKS is GitHub's "clean, but with post-merge hooks" state.
export function readyToMerge(snap) {
  return (
    isGreen(snap) &&
    snap.isDraft !== true &&
    (snap.mergeState === "CLEAN" || snap.mergeState === "HAS_HOOKS") &&
    snap.autoMerge !== true &&
    snap.queued !== true
  );
}

export function emptyProgress() {
  return { greenSha: null, queued: false, ended: null, landing: null };
}

// Decides what to tell the conversation about a change's progress.
//   prev: emptyProgress() shape, or null the first time.
//   snap: the pull request, with `queued` (in the merge queue or not).
//   baseChecks: checks on the merge commit, or null when not read this pass.
// Returns { events, state }. Events, each sent once:
//   { kind: "green" }                  all checks passed on the current commit
//   { kind: "dequeued" }               left the merge queue without merging
//   { kind: "merged" }                 merged
//   { kind: "closed" }                 closed without merging
//   { kind: "landed" }                 the base branch's checks passed after it
//   { kind: "base-failing", failing }  they did not
export function decideProgress(prev, snap, baseChecks, now) {
  const state = { ...emptyProgress(), ...(prev ?? {}) };
  const events = [];
  // The first read only takes stock, so watching a pull request that is
  // already green, queued or merged does not announce old news.
  const first = prev === null || prev === undefined;

  if (snap.state === "OPEN") {
    state.ended = null;
    state.landing = null;
    const green = isGreen(snap);
    if (green && state.greenSha !== snap.headSha) {
      if (!first) events.push({ kind: "green" });
      state.greenSha = snap.headSha;
    }
    // A new commit, or a check starting again (a re-run on the same commit
    // included), makes "green" news once more.
    if (!green && state.greenSha) {
      state.greenSha = null;
    }
    if (state.queued && !snap.queued && !first)
      events.push({ kind: "dequeued" });
    state.queued = snap.queued === true;
    return { events, state };
  }

  state.queued = false;
  if (snap.state !== "MERGED") {
    if (state.ended !== "closed" && !first) events.push({ kind: "closed" });
    state.ended = "closed";
    state.landing = null;
    return { events, state };
  }

  if (state.ended !== "merged") {
    state.ended = "merged";
    if (first) {
      // Merged before we ever saw it open: not ours to follow.
      state.landing = { phase: "done", since: now };
    } else {
      events.push({ kind: "merged" });
      state.landing = { phase: "watching", since: now };
    }
  }
  const landing = state.landing;
  const canRecover =
    landing?.phase === "done" &&
    landing?.result === "failing" &&
    Array.isArray(baseChecks);
  if (landing?.phase !== "watching" && !canRecover) return { events, state };

  const age = now - landing.since;
  if (age >= LANDING_TIMEOUT_MS) {
    state.landing = {
      ...landing,
      phase: "done",
      result: landing.result ?? "unknown",
    };
    return { events, state };
  }
  if (!baseChecks) return { events, state };
  if (baseChecks.length === 0) {
    if (age >= LANDING_QUIET_MS) {
      state.landing = { ...landing, phase: "done", result: "none" };
    }
    return { events, state };
  }
  const failing = baseChecks.filter((c) => c.bucket === "fail");
  const running = baseChecks.some((c) => c.bucket === "pending");
  if (failing.length > 0) {
    // Say so as soon as one fails (once), but keep watching until timeout in
    // case the check is re-run and passes.
    if (landing.result !== "failing") {
      events.push({ kind: "base-failing", failing });
    }
    state.landing = { ...landing, phase: "watching", result: "failing" };
  } else if (!running && age >= LANDING_SETTLE_MS) {
    events.push({ kind: "landed" });
    state.landing = { ...landing, phase: "done", result: "healthy" };
  } else if (running && landing.result === "failing") {
    state.landing = { ...landing, phase: "watching", result: undefined };
  }
  return { events, state };
}

// True while the base branch is still being watched after a merge.
export function landingActive(watch) {
  return watch?.progress?.landing?.phase === "watching";
}

// One line per event, for the message sent to the conversation.
export function progressLines(pr, events) {
  const lines = [];
  for (const event of events) {
    if (event.kind === "green") {
      lines.push(
        `All checks have passed on commit ${(pr.headSha ?? "").slice(0, 12)}. Nothing is needed from you for CI.`,
      );
    } else if (event.kind === "dequeued") {
      lines.push(
        "This pull request left the merge queue without merging. Check why on the pull request page before queueing it again.",
      );
    } else if (event.kind === "merged") {
      lines.push(
        `This pull request has merged into \`${pr.base}\`. The checks that run on \`${pr.base}\` are now being watched; you will be told how they end.`,
      );
    } else if (event.kind === "closed") {
      lines.push("This pull request was closed without merging.");
    } else if (event.kind === "landed") {
      lines.push(
        `The checks on \`${pr.base}\` passed after this merge. The change has landed cleanly; nothing more is needed.`,
      );
    } else if (event.kind === "base-failing") {
      lines.push(
        `Checks on \`${pr.base}\` are failing after this merge:`,
        ...event.failing.map((c) => `- ${c.name}${c.url ? ` ${c.url}` : ""}`),
        `Look at the failing logs and work out whether this merge caused it. If it did, open a fix or a revert as a new pull request; do not push to \`${pr.base}\` directly.`,
      );
    }
  }
  return lines;
}

export function progressTitle(events) {
  const names = {
    green: "checks passed",
    dequeued: "left the merge queue",
    merged: "merged",
    closed: "closed",
    landed: "landed cleanly",
    "base-failing": "base branch failing",
  };
  return events.map((e) => names[e.kind]).join(", ");
}

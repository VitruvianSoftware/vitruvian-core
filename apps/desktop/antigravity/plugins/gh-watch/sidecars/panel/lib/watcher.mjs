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

/* global setInterval, clearInterval */

// The polling loop. All I/O is injected, so the loop itself is unit tested.

import { countChecks, decide, emptyState } from "./decide.mjs";
import { recordFlakes, spotFlakes, tagFlaky } from "./flakes.mjs";
import { NOTE_TTL_MS, parseNote } from "./inbox.mjs";
import {
  decideProgress,
  landingActive,
  progressTitle,
  readyToMerge,
} from "./landing.mjs";
import { extractFailureExcerpt, parseCheckUrl } from "./logs.mjs";
import {
  composeMessage,
  decideConflict,
  decideFeedback,
  messageTitle,
} from "./notices.mjs";
import {
  RETURN_FLOOR_MS,
  intervalMs,
  modeOf,
  panelOpen,
  passDue,
} from "./pace.mjs";
import { reviewStatus } from "./reviews.mjs";

// How often the watcher looks at the clock. A pass only runs when one is due,
// so this costs nothing and lets a changed setting take effect at once.
export const TICK_MS = 5_000;
const MAX_BACKOFF_PASSES = 16;

export class Watcher {
  #store;
  #fetchPr;
  #fetchFeedback;
  #fetchQueue;
  #fetchCommitChecks;
  #fetchFailureLog;
  #resolvePr;
  #inbox;
  #sendMessage;
  #now;
  #pass = 0;
  #running = false;
  #timer = null;
  #lastPassAt = 0;
  #panelSeenAt = 0;

  constructor({
    store,
    fetchPr,
    fetchFeedback = async () => [],
    fetchQueue = async () => ({ queued: false, position: null }),
    fetchCommitChecks = async () => [],
    fetchFailureLog = null,
    resolvePr = null,
    inbox = null,
    sendMessage,
    now = Date.now,
  }) {
    this.#store = store;
    this.#fetchPr = fetchPr;
    this.#fetchFeedback = fetchFeedback;
    this.#fetchQueue = fetchQueue;
    this.#fetchCommitChecks = fetchCommitChecks;
    this.#fetchFailureLog = fetchFailureLog;
    this.#resolvePr = resolvePr;
    this.#inbox = inbox;
    this.#sendMessage = sendMessage;
    this.#now = now;
  }

  start(tickMs = TICK_MS) {
    if (this.#timer) return;
    this.#timer = setInterval(() => void this.tick(), tickMs);
    this.#timer.unref?.();
    void this.pass();
  }

  stop() {
    if (this.#timer) clearInterval(this.#timer);
    this.#timer = null;
  }

  // Starts watching the pull requests agents have just opened, from the
  // notes the sign-up hook leaves. A note whose pull request cannot be found
  // yet is kept and tried again until it is too old.
  async signUp() {
    if (!this.#inbox || !this.#resolvePr) return;
    const enabled = this.#store.settings().autoWatch;
    for (const note of this.#inbox.list()) {
      const parsed = enabled ? parseNote(note.text) : null;
      if (!parsed) {
        this.#inbox.remove(note.file);
        continue;
      }
      // A note can name several pull requests. It is kept while any of them
      // cannot be found yet; the ones already added are skipped next time.
      let missing = false;
      for (const ref of parsed.refs) {
        let snap;
        try {
          snap = await this.#resolvePr(ref, parsed.cwd);
        } catch {
          missing = true;
          continue;
        }
        if (snap.state !== "OPEN") continue;
        const key = `${snap.repo.toLowerCase()}#${snap.number}`;
        // Never take over a pull request someone is already watching.
        if (this.#store.get(key)) continue;
        this.#store.put({
          key,
          repo: snap.repo,
          number: snap.number,
          conversationId: parsed.conversationId,
          autoFix: true,
          comments: false,
          updates: true,
          addedAt: this.#now(),
          // "hook" for a `gh pr create` the hook saw, "agent" for one the
          // agent signed up by hand.
          addedBy: ref === "" ? "hook" : "agent",
          closed: false,
          readFailures: 0,
        });
        await this.check(key);
      }
      if (!missing || this.#now() - note.at > NOTE_TTL_MS)
        this.#inbox.remove(note.file);
    }
  }

  // Runs a pass if one is due at the current pace.
  async tick() {
    await this.signUp();
    const { mode } = this.status();
    const due = passDue({
      now: this.#now(),
      lastPassAt: this.#lastPassAt,
      settings: this.#store.settings(),
      mode,
    });
    if (due) await this.pass();
  }

  // The panel says whether it is showing. Coming back to it after it was
  // away checks everything at once, unless a pass ran moments ago.
  async notePresence(visible) {
    const now = this.#now();
    const wasOpen = panelOpen(this.#panelSeenAt, now);
    this.#panelSeenAt = visible ? now : 0;
    if (visible && !wasOpen && now - this.#lastPassAt >= RETURN_FLOOR_MS) {
      await this.pass();
    }
  }

  // What the panel shows about the pace.
  status() {
    const now = this.#now();
    const settings = this.#store.settings();
    const { mode, reason } = modeOf({
      watches: this.#store.list(),
      panelSeenAt: this.#panelSeenAt,
      now,
    });
    return {
      mode,
      reason,
      intervalSeconds: intervalMs(settings, mode) / 1000,
      lastPassAt: this.#lastPassAt,
    };
  }

  // One pass over every watched pull request. Never overlaps itself.
  async pass() {
    if (this.#running) return;
    this.#running = true;
    this.#lastPassAt = this.#now();
    const pass = this.#pass++;
    try {
      const settings = this.#store.settings();
      const now = this.#now();
      for (const watch of this.#store.list()) {
        if (watch.closed) {
          // A closed pull request stays in the list for a while, so the
          // panel can show that it merged, and is then dropped. Until then
          // it is re-read at the slow pace, which is how a reopened one is
          // noticed.
          const closedFor = now - (watch.closedAt ?? watch.checkedAt ?? now);
          if (closedFor >= settings.removeClosedHours * 3_600_000) {
            this.#store.remove(watch.key);
          } else if (landingActive(watch)) {
            // Just merged: the base branch's checks are followed at the
            // normal pace until they finish.
            await this.check(watch.key);
          } else if (
            now - (watch.checkedAt ?? 0) >=
            settings.slowSeconds * 1000
          ) {
            await this.check(watch.key);
          }
          continue;
        }
        // A pull request that keeps failing to read is retried less often.
        const every = Math.min(
          2 ** (watch.readFailures ?? 0),
          MAX_BACKOFF_PASSES,
        );
        if (pass % every !== 0) continue;
        await this.check(watch.key);
      }
    } finally {
      this.#running = false;
    }
  }

  // Reads one pull request and wakes its conversation if it should.
  async check(key, { forceWake = false } = {}) {
    const watch = this.#store.get(key);
    if (!watch) return;
    const now = this.#now();
    let snap;
    try {
      snap = await this.#fetchPr(watch.repo, watch.number);
    } catch (err) {
      this.#store.put({
        ...watch,
        readFailures: (watch.readFailures ?? 0) + 1,
        lastError: err.message,
        checkedAt: now,
      });
      return;
    }

    const next = {
      ...watch,
      title: snap.title,
      url: snap.url,
      branch: snap.branch,
      headSha: snap.headSha,
      prState: snap.state,
      isDraft: snap.isDraft,
      autoMerge: snap.autoMerge === true,
      counts: countChecks(snap.checks),
      failing: snap.checks
        .filter((c) => c.bucket === "fail")
        .map((c) => c.name),
      failingChecks: snap.checks
        .filter((c) => c.bucket === "fail")
        .map((c) => ({ name: c.name, url: c.url })),
      review: reviewStatus(snap),
      reviewDecision: snap.reviewDecision,
      latestReviews: snap.latestReviews,
      reviewRequests: snap.reviewRequests,
      closed: snap.state !== "OPEN",
      closedAt: snap.state !== "OPEN" ? (watch.closedAt ?? now) : undefined,
      readFailures: 0,
      lastError: null,
      checkedAt: now,
    };

    // Remember checks that failed and then passed on the same commit.
    const spot = spotFlakes(watch.flakeSeen, snap);
    next.flakeSeen = spot.seen;
    if (spot.flaked.length > 0) {
      this.#store.setFlakes(
        recordFlakes(this.#store.flakes(), watch.repo, spot.flaked, now),
      );
    }
    next.failingChecks = tagFlaky(
      this.#store.flakes(),
      watch.repo,
      next.failingChecks,
      now,
    );

    // Where the change has got to: green, queued, merged, landed. The state
    // is always kept for the panel; the news is only sent when the pull
    // request's updates switch is on.
    let queue = { queued: false, position: null };
    let baseChecks = null;
    try {
      const settled =
        !next.closed && next.counts.pending === 0 && next.counts.fail === 0;
      if (
        !next.closed &&
        (settled || watch.queued || watch.autoMerge || snap.autoMerge)
      ) {
        queue = await this.#fetchQueue(watch.repo, watch.number);
      }
      const shouldCheckBase =
        snap.state === "MERGED" &&
        snap.mergeCommit &&
        (landingActive(watch) ||
          watch.progress?.landing?.result === "failing" ||
          (watch.progress?.ended === "merged" && !watch.baseCounts));
      if (shouldCheckBase) {
        baseChecks = await this.#fetchCommitChecks(
          watch.repo,
          snap.mergeCommit,
        );
      }
    } catch (err) {
      next.lastError = `Could not read merge progress: ${err.message}`;
    }
    if (snap.state === "MERGED") {
      if (baseChecks && baseChecks.length > 0) {
        next.counts = countChecks(baseChecks);
        next.failing = baseChecks
          .filter((c) => c.bucket === "fail")
          .map((c) => c.name);
        next.failingChecks = baseChecks
          .filter((c) => c.bucket === "fail")
          .map((c) => ({ name: c.name, url: c.url }));
        next.baseCounts = true;
      } else if (watch.baseCounts && watch.counts) {
        next.counts = watch.counts;
        next.failing = watch.failing ?? [];
        next.failingChecks = watch.failingChecks ?? [];
        next.baseCounts = true;
      }
    }
    const journey = decideProgress(
      watch.progress,
      { ...snap, queued: queue.queued },
      baseChecks,
      now,
    );
    next.progress = journey.state;
    next.queued = queue.queued;
    next.queuePosition = queue.position;
    next.readyToMerge = readyToMerge({ ...snap, queued: queue.queued });
    const progress = watch.updates ? journey.events : [];

    if (next.closed) {
      if (progress.length === 0) {
        this.#store.put(next);
        return;
      }
      await this.#deliver(watch, next, snap, { progress }, now);
      return;
    }

    // Failing checks and merge conflicts share the auto-fix switch.
    let failing = [];
    let conflict = null;
    if (watch.autoFix || forceWake) {
      const ci = decide(
        forceWake ? emptyState() : (watch.decision ?? emptyState()),
        snap,
        now,
        {
          holdMs: forceWake ? 0 : this.#store.settings().holdSeconds * 1000,
        },
      );
      failing = tagFlaky(this.#store.flakes(), watch.repo, ci.wake, now);
      next.decision = ci.state;
      const merge = decideConflict(
        forceWake ? null : (watch.conflict ?? null),
        snap,
        now,
      );
      conflict = merge.notice;
      next.conflict = merge.state;
    }
    next.conflicting = snap.mergeable === "CONFLICTING";

    // Review feedback has its own switch. A failed read only costs this
    // pass: the same feedback is still new on the next one.
    let feedback = [];
    if (watch.comments) {
      try {
        const items = await this.#fetchFeedback(watch.repo, watch.number);
        const seen = decideFeedback(watch.seenFeedback, items);
        feedback = seen.fresh;
        next.seenFeedback = seen.seen;
      } catch (err) {
        next.lastError = `Could not read review comments: ${err.message}`;
      }
    }

    if (
      failing.length === 0 &&
      !conflict &&
      feedback.length === 0 &&
      progress.length === 0
    ) {
      this.#store.put(next);
      return;
    }
    await this.#deliver(
      watch,
      next,
      snap,
      { failing, conflict, feedback, progress },
      now,
    );
  }

  // Sends one message for everything decided on this pass and records it.
  // If it cannot be delivered, what was decided is rolled back so the next
  // pass tries again.
  async #deliver(watch, next, snap, parts, now) {
    let { failing = [], conflict = null, feedback = [], progress = [] } = parts;
    if (failing.length > 0 && this.#fetchFailureLog) {
      let fetched = 0;
      const enriched = [];
      for (const check of failing) {
        if (!check.flaky && fetched < 2 && check.url) {
          const parsed = parseCheckUrl(check.url);
          if (parsed?.runId) {
            fetched += 1;
            try {
              const raw = await this.#fetchFailureLog(
                watch.repo,
                parsed.runId,
                parsed.jobId,
              );
              const excerpt = extractFailureExcerpt(raw, 25);
              if (excerpt) {
                enriched.push({ ...check, excerpt });
                continue;
              }
            } catch {
              // Best-effort log excerpt; never block the wake.
            }
          }
        }
        enriched.push(check);
      }
      failing = enriched;
    }
    const messageParts = { failing, conflict, feedback, progress };
    try {
      await this.#sendMessage(
        watch.conversationId,
        composeMessage(snap, messageParts),
        { title: messageTitle(snap, messageParts) },
      );
    } catch (err) {
      this.#store.put({
        ...next,
        decision: watch.decision,
        conflict: watch.conflict,
        seenFeedback: watch.seenFeedback,
        progress: watch.progress,
        lastError: `Could not wake the conversation: ${err.message}`,
      });
      return;
    }
    const about = [
      ...(progress.length > 0 ? [progressTitle(progress)] : []),
      ...failing.map((c) => c.name),
      ...(conflict ? ["merge conflicts"] : []),
      ...(feedback.length > 0
        ? [
            `${feedback.length} review comment${feedback.length === 1 ? "" : "s"}`,
          ]
        : []),
    ];
    this.#store.put({
      ...next,
      wakes: (watch.wakes ?? 0) + 1,
      lastWakeAt: now,
      lastWakeChecks: about,
    });
  }
}

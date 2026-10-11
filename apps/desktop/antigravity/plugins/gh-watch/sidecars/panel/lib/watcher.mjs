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
      let snap;
      try {
        snap = await this.#resolvePr("", parsed.cwd);
      } catch {
        if (this.#now() - note.at > NOTE_TTL_MS) this.#inbox.remove(note.file);
        continue;
      }
      this.#inbox.remove(note.file);
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
        addedBy: "hook",
        closed: false,
        readFailures: 0,
      });
      await this.check(key);
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
  async check(key) {
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

    // Where the change has got to: green, queued, merged, landed. The state
    // is always kept for the panel; the news is only sent when the pull
    // request's updates switch is on.
    let queue = { queued: false, position: null };
    let baseChecks = null;
    try {
      const settled =
        !next.closed && next.counts.pending === 0 && next.counts.fail === 0;
      if (settled || watch.queued) {
        queue = await this.#fetchQueue(watch.repo, watch.number);
      }
      if (snap.state === "MERGED" && snap.mergeCommit && landingActive(watch)) {
        baseChecks = await this.#fetchCommitChecks(
          watch.repo,
          snap.mergeCommit,
        );
      }
    } catch (err) {
      next.lastError = `Could not read merge progress: ${err.message}`;
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
    if (watch.autoFix) {
      const ci = decide(watch.decision ?? emptyState(), snap, now, {
        holdMs: this.#store.settings().holdSeconds * 1000,
      });
      failing = tagFlaky(this.#store.flakes(), watch.repo, ci.wake, now);
      next.decision = ci.state;
      const merge = decideConflict(watch.conflict ?? null, snap, now);
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
    const {
      failing = [],
      conflict = null,
      feedback = [],
      progress = [],
    } = parts;
    try {
      await this.#sendMessage(
        watch.conversationId,
        composeMessage(snap, parts),
        { title: messageTitle(snap, parts) },
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

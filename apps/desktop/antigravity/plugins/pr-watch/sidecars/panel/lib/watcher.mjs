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

import { countChecks, decide, emptyState, wakeMessage } from "./decide.mjs";
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
  #sendMessage;
  #now;
  #pass = 0;
  #running = false;
  #timer = null;
  #lastPassAt = 0;
  #panelSeenAt = 0;

  constructor({ store, fetchPr, sendMessage, now = Date.now }) {
    this.#store = store;
    this.#fetchPr = fetchPr;
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

  // Runs a pass if one is due at the current pace.
  async tick() {
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
      for (const watch of this.#store.list()) {
        if (watch.closed) continue;
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
      readFailures: 0,
      lastError: null,
      checkedAt: now,
    };

    if (next.closed || !watch.autoFix) {
      // Status only. Turning auto-fix on later reports whatever is failing
      // at that point.
      this.#store.put(next);
      return;
    }

    const { wake, state } = decide(watch.decision ?? emptyState(), snap, now, {
      holdMs: this.#store.settings().holdSeconds * 1000,
    });
    if (wake.length === 0) {
      this.#store.put({ ...next, decision: state });
      return;
    }

    try {
      await this.#sendMessage(
        watch.conversationId,
        wakeMessage({ ...snap }, wake),
        {
          title: `CI failing on ${snap.repo}#${snap.number}`,
        },
      );
    } catch (err) {
      // Not delivered: leave the decision state as it was so the next pass
      // tries again.
      this.#store.put({
        ...next,
        lastError: `Could not wake the conversation: ${err.message}`,
      });
      return;
    }
    this.#store.put({
      ...next,
      decision: state,
      wakes: (watch.wakes ?? 0) + 1,
      lastWakeAt: now,
      lastWakeChecks: wake.map((c) => c.name),
    });
  }
}

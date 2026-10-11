// Copyright (c) 2026 VitruvianSoftware
//
// SPDX-License-Identifier: MIT

/* global setInterval, clearInterval */

// The polling loop. All I/O is injected, so the loop itself is unit tested.

import { countChecks, decide, emptyState, wakeMessage } from "./decide.mjs";

export const POLL_INTERVAL_MS = 30_000;
const MAX_BACKOFF_PASSES = 16;

export class Watcher {
  #store;
  #fetchPr;
  #sendMessage;
  #now;
  #holdMs;
  #pass = 0;
  #running = false;
  #timer = null;

  constructor({ store, fetchPr, sendMessage, now = Date.now, holdMs }) {
    this.#store = store;
    this.#fetchPr = fetchPr;
    this.#sendMessage = sendMessage;
    this.#now = now;
    this.#holdMs = holdMs;
  }

  start(intervalMs = POLL_INTERVAL_MS) {
    if (this.#timer) return;
    this.#timer = setInterval(() => void this.pass(), intervalMs);
    this.#timer.unref?.();
    void this.pass();
  }

  stop() {
    if (this.#timer) clearInterval(this.#timer);
    this.#timer = null;
  }

  // One pass over every watched pull request. Never overlaps itself.
  async pass() {
    if (this.#running) return;
    this.#running = true;
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
      holdMs: this.#holdMs,
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

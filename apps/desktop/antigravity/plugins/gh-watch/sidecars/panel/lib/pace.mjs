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

import { cleanRepoList } from "./reviews.mjs";

// How often to poll, as pure logic so it runs under `node --test`.
//
// Fast while something can change soon (the panel is showing, a check is
// still running, or a pull request has not been read yet); slow once every
// watched pull request has settled.

export const DEFAULT_SETTINGS = Object.freeze({
  fastSeconds: 30,
  slowSeconds: 300,
  holdSeconds: 300,
  mergeMethod: "squash",
  autoWatch: true,
  removeClosedHours: 24,
  // Repositories left out of "Waiting on your review".
  hiddenReviewRepos: Object.freeze([]),
});

export const LIMITS = Object.freeze({
  fastSeconds: [10, 600],
  slowSeconds: [30, 3600],
  holdSeconds: [0, 1800],
  removeClosedHours: [0, 720],
});

export const MERGE_METHODS = Object.freeze(["squash", "merge", "rebase"]);

// The panel reports that it is showing every few seconds; it counts as open
// until that long has passed without a report.
export const PRESENCE_TTL_MS = 30_000;

// A return to the panel triggers an immediate pass unless one ran this
// recently.
export const RETURN_FLOOR_MS = 10_000;

function clampInt(value, [min, max], fallback) {
  const n = Math.round(Number(value));
  if (!Number.isFinite(n)) return fallback;
  return Math.min(max, Math.max(min, n));
}

// Returns valid settings: `input` laid over `base`, each number clamped to
// its limits and the slow interval never shorter than the fast one.
export function cleanSettings(input = {}, base = DEFAULT_SETTINGS) {
  const merged = { ...DEFAULT_SETTINGS, ...base, ...input };
  const fastSeconds = clampInt(
    merged.fastSeconds,
    LIMITS.fastSeconds,
    DEFAULT_SETTINGS.fastSeconds,
  );
  const slowSeconds = Math.max(
    fastSeconds,
    clampInt(
      merged.slowSeconds,
      LIMITS.slowSeconds,
      DEFAULT_SETTINGS.slowSeconds,
    ),
  );
  const holdSeconds = clampInt(
    merged.holdSeconds,
    LIMITS.holdSeconds,
    DEFAULT_SETTINGS.holdSeconds,
  );
  const mergeMethod = MERGE_METHODS.includes(merged.mergeMethod)
    ? merged.mergeMethod
    : DEFAULT_SETTINGS.mergeMethod;
  const autoWatch = merged.autoWatch !== false;
  const removeClosedHours = clampInt(
    merged.removeClosedHours,
    LIMITS.removeClosedHours,
    DEFAULT_SETTINGS.removeClosedHours,
  );
  return {
    fastSeconds,
    slowSeconds,
    holdSeconds,
    mergeMethod,
    autoWatch,
    removeClosedHours,
    hiddenReviewRepos: cleanRepoList(merged.hiddenReviewRepos),
  };
}

export function panelOpen(panelSeenAt, now) {
  return panelSeenAt > 0 && now - panelSeenAt < PRESENCE_TTL_MS;
}

// Picks the polling mode and says why, for the panel to show.
export function modeOf({ watches, panelSeenAt, now }) {
  // A merged pull request whose base branch is still being checked counts
  // as live work.
  if (watches.some((w) => w.progress?.landing?.phase === "watching"))
    return { mode: "fast", reason: "merged, watching the base branch" };
  const open = watches.filter((w) => !w.closed);
  if (open.length === 0) return { mode: "slow", reason: "nothing to watch" };
  if (panelOpen(panelSeenAt, now))
    return { mode: "fast", reason: "panel open" };
  if (open.some((w) => !w.counts))
    return { mode: "fast", reason: "not read yet" };
  if (open.some((w) => w.counts.pending > 0))
    return { mode: "fast", reason: "checks running" };
  return { mode: "slow", reason: "all checks settled" };
}

export function intervalMs(settings, mode) {
  return (mode === "fast" ? settings.fastSeconds : settings.slowSeconds) * 1000;
}

export function passDue({ now, lastPassAt, settings, mode }) {
  return now - lastPassAt >= intervalMs(settings, mode);
}

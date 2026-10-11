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

import {
  DEFAULT_SETTINGS,
  cleanSettings,
  intervalMs,
  modeOf,
  passDue,
} from "./pace.mjs";

const counts = (pending) => ({ pass: 1, fail: 0, pending, skip: 0, cancel: 0 });

test("cleanSettings falls back to defaults and clamps to limits", () => {
  assert.deepEqual(cleanSettings(), { ...DEFAULT_SETTINGS });
  assert.deepEqual(cleanSettings({ fastSeconds: 1, slowSeconds: 99999 }), {
    ...DEFAULT_SETTINGS,
    fastSeconds: 10,
    slowSeconds: 3600,
  });
  assert.equal(cleanSettings({ fastSeconds: "abc" }).fastSeconds, 30);
  assert.equal(cleanSettings({ holdSeconds: 0 }).holdSeconds, 0);
  assert.equal(cleanSettings({ mergeMethod: "yolo" }).mergeMethod, "squash");
  assert.equal(cleanSettings({ mergeMethod: "rebase" }).mergeMethod, "rebase");
  assert.equal(cleanSettings().autoWatch, true);
  assert.equal(cleanSettings().removeClosedHours, 24);
  assert.equal(cleanSettings({ removeClosedHours: 0 }).removeClosedHours, 0);
  assert.equal(
    cleanSettings({ removeClosedHours: 9999 }).removeClosedHours,
    720,
  );
  assert.equal(cleanSettings({ autoWatch: false }).autoWatch, false);
  assert.equal(
    cleanSettings({ fastSeconds: 20 }, { autoWatch: false }).autoWatch,
    false,
  );
});

test("the slow interval is never shorter than the fast one", () => {
  const s = cleanSettings({ fastSeconds: 120, slowSeconds: 60 });
  assert.equal(s.fastSeconds, 120);
  assert.equal(s.slowSeconds, 120);
});

test("cleanSettings keeps earlier choices that the new input does not mention", () => {
  const first = cleanSettings({ fastSeconds: 45 });
  assert.equal(cleanSettings({ slowSeconds: 600 }, first).fastSeconds, 45);
});

test("fast while the panel is open, even if everything has settled", () => {
  const watches = [{ counts: counts(0) }];
  assert.deepEqual(modeOf({ watches, panelSeenAt: 95_000, now: 100_000 }), {
    mode: "fast",
    reason: "panel open",
  });
  // The panel stops counting as open once its reports go stale.
  assert.equal(
    modeOf({ watches, panelSeenAt: 60_000, now: 100_000 }).mode,
    "slow",
  );
});

test("fast while a check is running or a pull request is unread", () => {
  assert.deepEqual(
    modeOf({ watches: [{ counts: counts(3) }], panelSeenAt: 0, now: 1 }),
    { mode: "fast", reason: "checks running" },
  );
  assert.deepEqual(modeOf({ watches: [{}], panelSeenAt: 0, now: 1 }), {
    mode: "fast",
    reason: "not read yet",
  });
});

test("slow once everything has settled, or when only closed ones remain", () => {
  assert.deepEqual(
    modeOf({ watches: [{ counts: counts(0) }], panelSeenAt: 0, now: 1 }),
    { mode: "slow", reason: "all checks settled" },
  );
  assert.deepEqual(
    modeOf({
      watches: [{ closed: true, counts: counts(5) }],
      panelSeenAt: 0,
      now: 1,
    }),
    { mode: "slow", reason: "nothing to watch" },
  );
});

test("passDue follows the interval for the current mode", () => {
  const settings = cleanSettings({ fastSeconds: 30, slowSeconds: 300 });
  assert.equal(intervalMs(settings, "fast"), 30_000);
  assert.equal(intervalMs(settings, "slow"), 300_000);
  const at = (now, mode) => passDue({ now, lastPassAt: 0, settings, mode });
  assert.equal(at(29_999, "fast"), false);
  assert.equal(at(30_000, "fast"), true);
  assert.equal(at(30_000, "slow"), false);
  assert.equal(at(300_000, "slow"), true);
});

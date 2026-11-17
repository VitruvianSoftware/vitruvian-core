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

/**
 * @file Upstream-request accounting shared by the keyed tile proxies.
 *
 * A soft cap per UTC period, persisted as `{date, count}` so it survives a
 * restart. Nothing here is provider-specific: the caller picks the period by
 * the key it passes, and decides what happens over the cap.
 *
 * Zero dependencies and Cesium-free, so providers and browser helpers can
 * import it and node:test can exercise it directly.
 *
 * @module data/tileBudget
 */

/**
 * UTC calendar-day key for budget bucketing.
 *
 * @param {number} [epochMs=Date.now()] - Timestamp in ms.
 * @returns {string} 'YYYY-MM-DD' in UTC.
 */
export function utcDayKey(epochMs = Date.now()) {
  return new Date(epochMs).toISOString().slice(0, 10);
}

/**
 * Normalize a persisted budget state against the current period key.
 * Rolls the counter to zero when the period changes; replaces missing/corrupt
 * state. Returns the SAME object when it is already valid for `periodKey`
 * (cheap to call on every request).
 *
 * @param {{date:string, count:number}|null|undefined} state - Persisted state.
 * @param {string} periodKey - Current period key, e.g. from `utcDayKey`.
 * @returns {{date:string, count:number}} Valid state for `periodKey`.
 */
export function normalizeBudget(state, periodKey) {
  const valid =
    Boolean(state) &&
    state.date === periodKey &&
    Number.isFinite(state.count) &&
    state.count >= 0;
  return valid ? state : { date: periodKey, count: 0 };
}

/**
 * Whether the soft cap for the current period has been reached.
 *
 * @param {{count:number}} state - Normalized budget state.
 * @param {number} limit - Budget per period; non-positive/invalid never blocks.
 * @returns {boolean} True when `count >= limit`.
 */
export function isOverBudget(state, limit) {
  if (!Number.isFinite(limit) || limit <= 0) return false;
  return state.count >= limit;
}

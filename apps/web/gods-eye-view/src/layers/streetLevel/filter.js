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

import { FILTER_DEFAULT, MAX_SINCE_DAYS, PANO_MODES } from './policy.js';

const DAY_MS = 86_400_000;

/**
 * Merge a partial filter change; unknown pano modes and invalid day counts
 * keep the current value.
 * @param {{pano?: string, sinceDays?: number}|null} next
 * @param {{pano: string, sinceDays: number}} [current]
 * @returns {{pano: string, sinceDays: number}}
 */
export function normalizeFilter(next, current = FILTER_DEFAULT) {
  const pano = PANO_MODES.includes(next?.pano) ? next.pano : current.pano;
  let sinceDays = current.sinceDays;
  if (next && 'sinceDays' in next) {
    const days = Number(next.sinceDays);
    if (Number.isInteger(days) && days >= 0)
      sinceDays = Math.min(days, MAX_SINCE_DAYS);
  }
  return { pano, sinceDays };
}

/** True when two filters would show the same imagery. */
export function sameFilter(a, b) {
  return a?.pano === b?.pano && a?.sinceDays === b?.sinceDays;
}

/**
 * Stored filter (relative days, stable in share links) to the absolute form
 * providers compare capture times against.
 * @returns {{pano: string, sinceMs: number|null}}
 */
export function resolveFilter(filter, now = Date.now()) {
  const days = Number(filter?.sinceDays) || 0;
  return {
    pano: PANO_MODES.includes(filter?.pano) ? filter.pano : 'all',
    sinceMs: days > 0 ? now - days * DAY_MS : null,
  };
}

/**
 * Whether a capture passes the resolved filter: pano mode and an optional
 * earliest capture time.
 * @param {{isPano?: boolean, capturedAt?: number}} record
 * @param {{pano: string, sinceMs: number|null}|null} filter
 */
export function passesImageryFilter(record, filter) {
  if (!filter) return true;
  if (filter.pano === 'pano' && !record.isPano) return false;
  if (filter.pano === 'flat' && record.isPano) return false;
  if (
    Number.isFinite(filter.sinceMs) &&
    filter.sinceMs > 0 &&
    (record.capturedAt || 0) < filter.sinceMs
  )
    return false;
  return true;
}

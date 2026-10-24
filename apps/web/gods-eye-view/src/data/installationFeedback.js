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

import { msg } from '../i18n/marker.js';

// layers/installations/controls.js translates describeInstallationFeedback().
const REASONS = Object.freeze({
  rate_limited: msg('Overpass rate-limited'),
  timeout: msg('Overpass timed out'),
  query_failed: msg('Overpass could not complete the query'),
  tiles_unavailable: msg('Map tiles temporarily unavailable'),
  names_unavailable: msg('Mapped names temporarily unavailable'),
});
const FALLBACK_REASON = msg('Overpass temporarily unavailable');

/**
 * Mapped-site availability as a message to render, without claiming an
 * unobserved overload. Either `{ text, reason?, seconds? }`, where `text` is
 * English (`{reason}` / `{seconds}` placeholders, `reason` English too), or
 * `{ count, km }` for a found-sites count (`km` is null for the view).
 * @param {object} [stats]
 * @param {number} [now]
 * @returns {{text: string, reason?: string, seconds?: number}|{count: number, km: ?number}}
 */
export function describeInstallationFeedback(stats = {}, now = Date.now()) {
  const reason = REASONS[stats.failureReason] || FALLBACK_REASON;
  if (stats.loading)
    return {
      text: stats.retrying
        ? msg('Retrying mapped sites…')
        : msg('Fetching mapped sites…'),
    };
  if (stats.retryAt > 0) {
    const seconds = Math.max(0, Math.ceil((stats.retryAt - now) / 1000));
    return seconds
      ? { text: msg('{reason} — retrying in {seconds}s'), reason, seconds }
      : { text: msg('{reason} — retry pending'), reason };
  }
  if (stats.status === 'unavailable') return { text: reason };
  if (stats.status === 'zoom-in')
    return { text: msg('Zoom in to search mapped installations') };
  if (stats.stale) return { text: msg('Showing cached mapped sites') };
  if (stats.status === 'idle') return { text: msg('Mapped sites not loaded') };
  // With a count, say what was found and where; an empty area is not "loaded".
  if (Number.isFinite(stats.count)) {
    const km =
      stats.coverage?.kind === 'subject' &&
      Number.isFinite(stats.coverage.radiusM)
        ? Math.round(stats.coverage.radiusM / 1000)
        : null;
    return { count: stats.count, km: km || null };
  }
  return { text: msg('Mapped sites loaded') };
}

/** Explain mapped-site availability in English. */
export function installationFeedback(stats = {}, now = Date.now()) {
  const feedback = describeInstallationFeedback(stats, now);
  if (feedback.text !== undefined)
    return feedback.text
      .replace('{reason}', feedback.reason)
      .replace('{seconds}', feedback.seconds);
  const where = feedback.km
    ? ` within ${feedback.km} km of the contact`
    : ' in view';
  if (feedback.count === 0) return `No mapped sites${where}`;
  return `${feedback.count} mapped site${feedback.count === 1 ? '' : 's'}${where}`;
}

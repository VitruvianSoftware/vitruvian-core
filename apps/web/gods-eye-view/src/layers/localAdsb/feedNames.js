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
 * Names for the server's decoder feeds, shared by the Local ADS-B row status
 * and the Radio card. Pure; no imports, so any surface may use it.
 */

/**
 * Display name of one feed: its band, or its ordinal label ("978 MHz UAT #2")
 * when another configured feed shares the band.
 * @param {object} feed Feed status from the route.
 * @param {object[]} [feeds] Every configured feed.
 * @returns {string}
 */
export function localReceiverFeedName(feed, feeds = []) {
  const band = feed?.band;
  if (!band) return feed?.label || 'feed';
  const sharing = feeds.filter((other) => other?.band === band);
  if (sharing.length < 2) return band;
  if (typeof feed.label === 'string' && feed.label.includes('#'))
    return feed.label;
  return `${feed.label || band} #${sharing.indexOf(feed) + 1}`;
}

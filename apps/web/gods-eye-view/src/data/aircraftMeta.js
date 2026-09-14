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

// src/data/aircraftMeta.js
/**
 * Sticky per-aircraft metadata merge: once a field has resolved for an
 * aircraft, a later snapshot that MISSES the field (empty/null — OpenSky and
 * adsb.lol both do this intermittently) must not regress it. A later snapshot
 * that CHANGES the field always wins. Pattern from skylight (MIT)
 * server/src/datasource.ts "sticky enrichment".
 */

export function stickyText(next, prev) {
  const n = String(next || '').trim();
  if (n) return n;
  const p = String(prev || '').trim();
  return p || '';
}

export function stickyNumber(next, prev, fallback) {
  if (Number.isFinite(next)) return next;
  if (Number.isFinite(prev)) return prev;
  return fallback;
}

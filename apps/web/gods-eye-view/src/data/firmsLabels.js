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
 * @module firmsLabels
 * @description FIRMS-specific presentation formatting retained after the
 * dedicated card canvas moved into the shared world-overlay host.
 */

/** Shipped ambient FIRMS card ceiling. Selected fires bypass this cohort. */
export const FIRMS_AMBIENT_COHORT_LIMIT = 18;
export const FIRMS_OVERLAY_SOURCE_ID = 'firms';

/** Refetch-stable identity for one FIRMS detection, including its source feed. */
export function fireDetectionKey(fire) {
  const lat = Number.isFinite(fire?.lat) ? fire.lat.toFixed(4) : 'x';
  const lon = Number.isFinite(fire?.lon) ? fire.lon.toFixed(4) : 'x';
  const acq = Number.isFinite(fire?.acqMs) && fire.acqMs > 0 ? String(fire.acqMs) : '0';
  const source = satelliteShortName(fire?.satellite)
    || String(fire?.sensor || '').trim().toUpperCase()
    || 'x';
  return `firms:${lat}:${lon}:${acq}:${source}`;
}

/** Severity accent palette — matches the FIRMS glow-sprite color stops. */
const ACCENT_RGB = Object.freeze({
  red: '224, 82, 82',
  orange: '240, 178, 62',
  yellow: '244, 227, 108',
});

/**
 * Severity stop name → "r, g, b" accent string (defaults to yellow).
 * @param {string} stopName - 'red' | 'orange' | 'yellow'.
 * @returns {string}
 */
export function accentForSeverity(stopName) {
  return ACCENT_RGB[stopName] || ACCENT_RGB.yellow;
}

/** Raw FIRMS satellite code → short display name (N = Suomi NPP). */
export function satelliteShortName(satellite) {
  const s = String(satellite || '').trim().toUpperCase();
  if (s === 'N20' || s === 'NOAA-20') return 'N20';
  if (s === 'N21' || s === 'NOAA-21') return 'N21';
  if (s === 'N' || s === 'NPP' || s === 'SUOMI NPP') return 'SNPP';
  return s ? s.slice(0, 6) : '';
}

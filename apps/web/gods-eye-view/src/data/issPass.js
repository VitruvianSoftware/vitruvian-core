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

// src/data/issPass.js
/**
 * Next-ISS-pass prediction. Kept as a thin wrapper over satellitePass.js so the
 * original findNextIssPass signature and defaults still work.
 */
import { findNextSatellitePass, lookAnglesAt } from './satellitePass.js';

export { lookAnglesAt };

/**
 * Predict the next ISS pass over an observer location.
 * @param {Object} options
 * @param {Object} options.satrec SGP4 satellite record
 * @param {number} options.latDeg Observer latitude in degrees [-90, 90]
 * @param {number} options.lonDeg Observer longitude in degrees [-180, 180]
 * @param {number} options.fromMs UTC start time in milliseconds
 * @param {number} [options.minElevDeg=10] Elevation that defines rise and set, in degrees
 * @param {number} [options.horizonHours=24] Maximum search window in hours
 * @param {number} [options.coarseStepSec=30] Coarse search step in seconds
 * @param {number} [options.fineStepSec=5] Fine transit step in seconds for peak tracking and visibility
 * @param {boolean} [options.requireVisible=false] Require a naked-eye-visible pass
 * @returns {{ riseMs: number, setMs: number, maxElevDeg: number, maxElevMs: number, riseAzDeg: number, visible: boolean, sunlit: boolean, observerDark: boolean } | null}
 */
export function findNextIssPass({
  satrec,
  latDeg,
  lonDeg,
  fromMs,
  minElevDeg = 10,
  horizonHours = 24,
  coarseStepSec = 30,
  fineStepSec = 5,
  requireVisible = false,
}) {
  return findNextSatellitePass({
    satrec,
    latDeg,
    lonDeg,
    fromMs,
    minElevDeg,
    horizonHours,
    coarseStepSec,
    fineStepSec,
    requireVisible,
  });
}

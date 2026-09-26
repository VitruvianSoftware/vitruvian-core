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

export const GROUND_FLOOR_CLAMP_RADIUS_KM = 150;

export const GROUND_FLOOR_WARM_MAX_ALT_M = 4500;

/** Maximum feed fixes retained for dead reckoning. */
export const POSITION_HISTORY_LIMIT = 5;

export const LANDED_MISSING_POLL_LIMIT = 1;

export const MISSING_POLL_LIMIT = 3;

/** Cooldown in milliseconds after a transient source error. */
export const ERROR_BACKOFF_INTERVAL = 20000;

/** Local equirectangular distance used for viewer-proximate floor sampling. */
export function approxDistanceKm(lat1, lon1, lat2, lon2) {
  const dLat = (lat2 - lat1) * 111.32;
  const dLon =
    (lon2 - lon1) * 111.32 * Math.cos((((lat1 + lat2) / 2) * Math.PI) / 180);
  return Math.hypot(dLat, dLon);
}

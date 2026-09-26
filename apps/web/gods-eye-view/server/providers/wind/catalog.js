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

export const GFS_BUCKET = 'noaa-gfs-bdp-pds';

/** Build the public GFS object key. */
export function gfsObjectKey({ date, hour, forecastHour = 0 }) {
  const hh = String(hour).padStart(2, '0');
  return `gfs.${date}/${hh}/atmos/gfs.t${hh}z.pgrb2.0p25.f${String(forecastHour).padStart(3, '0')}`;
}

/** Select the latest GFS cycle that should be available. */
export function selectLatestGfsCycle(
  nowMs,
  { availabilityLagMs = 5 * 3600_000 } = {},
) {
  const d = new Date(nowMs - availabilityLagMs);
  const date = new Date(
    Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate()),
  );
  const hour = Math.floor(d.getUTCHours() / 6) * 6;
  date.setUTCHours(hour);
  return { date: date.toISOString().slice(0, 10).replaceAll('-', ''), hour };
}

/**
 * Round a time offset to the nearest published GFS forecast step so the field
 * shown is the one valid closest to now, not always the analysis (f000).
 * GFS 0.25° is hourly through f120, then every 3 h through f384.
 * @param {number} hours - Hours elapsed since the cycle run time.
 * @returns {number} A valid forecast step.
 */
export function nearestGfsStep(hours) {
  const value = Math.max(0, Number.isFinite(hours) ? hours : 0);
  const step = value <= 120 ? Math.round(value) : Math.round(value / 3) * 3;
  return Math.max(0, Math.min(384, step));
}

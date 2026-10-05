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

/** Smallest area asked for around the view, in kilometres. */
export const VIEW_AREA_MIN_RADIUS_KM = 10;
/** Largest area asked for; a wider view asks for every vessel instead. */
export const VIEW_AREA_MAX_RADIUS_KM = 450;

/**
 * The radius worth asking for from a camera this high, in kilometres: about
 * the height, so the area covers what a camera looking down shows. Null when
 * the view is wide enough that every vessel is wanted.
 */
export function viewAreaRadiusKm(heightM) {
  if (!Number.isFinite(heightM)) return null;
  const radiusKm = heightM / 1000;
  if (radiusKm > VIEW_AREA_MAX_RADIUS_KM) return null;
  return Math.max(VIEW_AREA_MIN_RADIUS_KM, radiusKm);
}

/**
 * Whether a view moved far enough from the last area asked for to ask
 * again: its radius changed by a quarter, or its center moved a quarter of
 * the radius. Switching between an area and every vessel always counts.
 */
export function viewAreaMovedEnough(previous, next) {
  if (!previous || !next) return previous !== next;
  if (Math.abs(next.radiusKm - previous.radiusKm) >= previous.radiusKm * 0.25)
    return true;
  const lat = ((previous.lat + next.lat) / 2) * (Math.PI / 180);
  const dLat = (next.lat - previous.lat) * 111.32;
  const dLon = (next.lon - previous.lon) * 111.32 * Math.cos(lat);
  return Math.hypot(dLat, dLon) >= previous.radiusKm * 0.25;
}

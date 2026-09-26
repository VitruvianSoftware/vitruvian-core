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

/** Validate a complete feed before replacing the last good earthquake snapshot. */
export function normalizeEarthquakeSnapshot(geojson) {
  if (!Array.isArray(geojson?.features)) return null;
  const rows = [];
  const ids = new Set();
  for (const [index, feature] of geojson.features.entries()) {
    const coordinates = feature?.geometry?.coordinates;
    const properties = feature?.properties;
    if (
      !Array.isArray(coordinates) ||
      coordinates.length < 2 ||
      !properties ||
      typeof properties !== 'object' ||
      Array.isArray(properties) ||
      (feature.geometry.type != null && feature.geometry.type !== 'Point')
    )
      return null;
    const [lon, lat, depthKm] = coordinates;
    const mag = properties.mag;
    if (
      !Number.isFinite(lon) ||
      Math.abs(lon) > 180 ||
      !Number.isFinite(lat) ||
      Math.abs(lat) > 90 ||
      (depthKm != null && !Number.isFinite(depthKm)) ||
      (mag != null && (!Number.isFinite(mag) || mag > 10))
    )
      return null;
    // A missing magnitude cannot establish that this event meets M2.5+.
    if (mag == null || mag < 2.5) continue;
    const stableId =
      feature.id == null || feature.id === ''
        ? `event-${index + 1}`
        : String(feature.id);
    if (ids.has(stableId)) return null;
    ids.add(stableId);
    rows.push({
      stableId,
      usgsId: feature.id ?? null,
      lon,
      lat,
      depthKm: depthKm ?? null,
      mag,
      place: typeof properties.place === 'string' ? properties.place : null,
      time: Number.isFinite(properties.time) ? properties.time : null,
    });
  }
  return rows;
}

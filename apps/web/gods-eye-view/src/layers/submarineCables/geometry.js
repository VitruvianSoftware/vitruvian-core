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

export function featureReference(feature) {
  const geometry = feature?.geometry;
  if (!geometry) return null;

  const props = feature?.properties || {};
  const propertyCoords = coordsFromProperty(props.coordinates);
  if (propertyCoords) {
    return {
      lon: propertyCoords[0],
      lat: propertyCoords[1],
    };
  }

  if (geometry.type === 'Point') {
    const coords = coordsFromPoint(geometry.coordinates);
    if (!coords) return null;
    return { lon: coords[0], lat: coords[1] };
  }

  const coords = [];
  collectLonLat(geometry.coordinates, coords);
  if (!coords.length) return null;

  let lonSum = 0;
  let latSum = 0;
  for (const [lon, lat] of coords) {
    lonSum += lon;
    latSum += lat;
  }
  return {
    lon: lonSum / coords.length,
    lat: latSum / coords.length,
  };
}

export function coordsFromProperty(value) {
  if (!Array.isArray(value) || value.length < 2) return null;
  const lon = Number(value[0]);
  const lat = Number(value[1]);
  if (!Number.isFinite(lon) || !Number.isFinite(lat)) return null;
  return [lon, lat];
}

export function coordsFromPoint(value) {
  if (!Array.isArray(value) || value.length < 2) return null;
  const lon = Number(value[0]);
  const lat = Number(value[1]);
  if (!Number.isFinite(lon) || !Number.isFinite(lat)) return null;
  return [lon, lat];
}

export function collectLonLat(value, out) {
  if (!Array.isArray(value)) return;
  if (typeof value[0] === 'number' && typeof value[1] === 'number') {
    const lon = Number(value[0]);
    const lat = Number(value[1]);
    if (Number.isFinite(lon) && Number.isFinite(lat)) {
      out.push([lon, lat]);
    }
    return;
  }
  for (const child of value) collectLonLat(child, out);
}

export function featureLabel(feature) {
  const props = feature?.properties || {};
  return String(props.name || props.id || feature?.id || '').trim();
}

export function normalizeFeatures(json, kind) {
  const features = Array.isArray(json?.features) ? json.features : [];
  return features.map((feature, index) => {
    const id = feature?.properties?.id || feature?.id || `${kind}-${index}`;
    return {
      ...feature,
      id: String(id),
    };
  });
}

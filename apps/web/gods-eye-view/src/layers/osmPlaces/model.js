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
 * OSM Places records: OpenStreetMap features found by a voice search,
 * mapped to plain analyst records. Pure — no Cesium.
 * @module layers/osmPlaces/model
 */

export const OSM_PLACES_LAYER_ID = 'osm-places';
/** A node and a way/relation of the same name this close are one site mapped twice. */
const SAME_SITE_M = 75;

/** Longest tag value kept; OSM names are open text that reaches the model. */
const MAX_TEXT = 120;

/**
 * A tag value as plain bounded text: control characters (newlines, tabs)
 * become spaces; format characters (bidi overrides, zero-width spaces) are
 * dropped, except the zero-width (non-)joiners Persian and Indic names spell
 * with; runs of whitespace collapse, and long values are cut with an
 * ellipsis.
 */
function text(value) {
  if (typeof value !== 'string') return null;
  const clean = value
    .replace(/\p{Cc}+/gu, ' ')
    .replace(/(?![\u200c\u200d])\p{Cf}/gu, '')
    .replace(/\s+/g, ' ')
    .trim();
  if (!clean) return null;
  // Cut on code points so an emoji's surrogate pair is never split.
  const chars = Array.from(clean);
  return chars.length <= MAX_TEXT
    ? clean
    : `${chars
        .slice(0, MAX_TEXT - 1)
        .join('')
        .trimEnd()}…`;
}

function distanceM(a, b) {
  const toRad = Math.PI / 180;
  const x = (b.lon - a.lon) * toRad * Math.cos(((a.lat + b.lat) / 2) * toRad);
  const y = (b.lat - a.lat) * toRad;
  return Math.hypot(x, y) * 6_371_000;
}

/**
 * One feature from `/api/osm/features` → an analyst record.
 * @param {{id: string, lat: number, lon: number, tags?: object}} feature
 * @param {{id: string, label: string}} preset
 * @returns {object|null}
 */
export function mapOsmFeature(feature, preset) {
  if (!Number.isFinite(feature?.lat) || !Number.isFinite(feature?.lon))
    return null;
  const tags = feature.tags || {};
  const [osmType] = String(feature.id || '').split('/');
  return {
    id: String(feature.id),
    lat: feature.lat,
    lon: feature.lon,
    name: text(tags['name:en']) || text(tags.name),
    kind: preset.id,
    operator: text(tags.operator) || text(tags.brand),
    emergency: text(tags.emergency),
    wheelchair: text(tags.wheelchair),
    openingHours: text(tags.opening_hours),
    city: text(tags['addr:city']),
    osmType: ['node', 'way', 'relation'].includes(osmType) ? osmType : null,
  };
}

/**
 * Remove double counting without merging distinct places:
 *
 * - the same OSM element (identical `type/id`) is counted once;
 * - a node and a way/relation with the same name within 75 m are one site
 *   mapped twice (a point on the building and the building outline), and
 *   merge;
 * - two nodes, or two ways, are always distinct places — two neighbouring
 *   cafés of one chain are two cafés — and never merge, whatever their names.
 *
 * @param {object[]} records
 * @returns {{records: object[], merged: number}}
 */
export function dedupeOsmRecords(records) {
  const kept = [];
  const seen = new Set();
  let merged = 0;
  for (const record of records) {
    if (seen.has(record.id)) {
      merged += 1;
      continue;
    }
    seen.add(record.id);
    const name = record.name?.toLowerCase();
    const isNode = record.osmType === 'node';
    const sameSite =
      name &&
      record.osmType &&
      kept.some(
        (other) =>
          other.osmType &&
          (other.osmType === 'node') !== isNode &&
          other.name?.toLowerCase() === name &&
          distanceM(other, record) <= SAME_SITE_M,
      );
    if (sameSite) merged += 1;
    else kept.push(record);
  }
  return { records: kept, merged };
}

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
 * Copy for the collapsed LOCATION panel's two-line mini-status.
 *
 * Two navigation paths reach it and both must land somewhere real:
 *  - a preset city/POI pill, which carries a curated `{name, pois}` record;
 *  - a free-text geocode search, which carries only the formatted address
 *    string ("Tokyo, Japan", "Tokyo Tower, 4 Chome-2-8 Shibakoen, …, Japan").
 *
 * Before this existed only the pill path was rendered, so a search left the
 * readout reporting "Location: --" while the camera sat over the destination.
 */

const EMPTY = Object.freeze({ city: '📍 Location: --', poi: 'Landmark: --' });

/** Split a geocoder `formatted_address` into its trimmed, non-empty segments. */
export function addressSegments(label) {
  return String(label ?? '')
    .split(',')
    .map((segment) => segment.trim())
    .filter(Boolean);
}

/**
 * Build the collapsed LOCATION mini-status lines.
 *
 * A preset city always wins: it is the curated record the camera was framed
 * from, and its POI name is more useful than any address string. A searched
 * label is used only when no preset city is active, which is exactly the state
 * a free-text search leaves behind.
 *
 * @param {Object} [input]
 * @param {{name: string, pois?: Array<{name: string}>}|null} [input.city]
 *   Active preset city record, or null.
 * @param {{name: string}|null} [input.currentPoi] - Currently framed preset POI.
 * @param {string} [input.searchedLabel] - Geocoded `formatted_address`.
 * @returns {{city: string, poi: string}} Line one and line two.
 */
export function locationMiniStatus({
  city = null,
  currentPoi = null,
  searchedLabel = '',
} = {}) {
  if (city?.name) {
    const fallbackPoi = city.pois?.[0] || null;
    return {
      city: `📍 ${city.name}`,
      poi: currentPoi?.name || fallbackPoi?.name || '--',
    };
  }

  const segments = addressSegments(searchedLabel);
  if (segments.length) {
    return {
      city: `📍 ${segments[0]}`,
      // The remaining address is the place's context ("Japan", "Minato City,
      // Tokyo, Japan"); the readout is ellipsised in CSS, so a long tail is
      // safe. A one-segment geocode ("Japan") has no context to show.
      poi: segments.length > 1 ? segments.slice(1).join(', ') : 'Searched location',
    };
  }

  return { ...EMPTY };
}

export default locationMiniStatus;

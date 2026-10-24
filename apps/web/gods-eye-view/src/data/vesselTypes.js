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
 * @module vesselTypes
 * @description AIS ship-type codes (ITU-R M.1371) to family names, with no
 * browser or i18n dependencies so the server-side query tools can use it.
 */

const NUMERIC_TYPE_SPECIALS = {
  30: 'FISHING',
  31: 'TOWING',
  32: 'TOWING',
  33: 'DREDGER',
  34: 'DIVE OPS',
  35: 'MILITARY',
  36: 'SAILING',
  37: 'PLEASURE',
  50: 'PILOT',
  51: 'SAR',
  52: 'TUG',
  53: 'PORT TENDER',
  54: 'ANTI-POLLUTION',
  55: 'LAW ENFORCE',
  58: 'MEDICAL',
};
const NUMERIC_TYPE_FAMILIES = {
  4: 'HIGH-SPEED',
  6: 'PASSENGER',
  7: 'CARGO',
  8: 'TANKER',
  9: 'OTHER',
};

/**
 * Resolve an AIS type to display text: bare numeric ship-type codes map to
 * family names ("71" → "CARGO"); text types pass through unchanged. Code 0
 * ("not available") and the reserved codes 100 to 255 name no type and
 * resolve to "".
 * @param {string} type Raw AIS type.
 * @returns {string}
 */
export function normalizeVesselType(type) {
  const text = String(type || '').trim();
  if (!text || !/^\d+$/.test(text)) return text;
  const code = Number(text);
  if (code <= 0 || code >= 100) return '';
  if (NUMERIC_TYPE_SPECIALS[code]) return NUMERIC_TYPE_SPECIALS[code];
  return NUMERIC_TYPE_FAMILIES[Math.floor(code / 10)] || 'OTHER';
}

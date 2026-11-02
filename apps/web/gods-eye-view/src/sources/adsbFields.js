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

/** A readsb rate field: a finite JSON number, else null. */
function rateField(value) {
  return typeof value === 'number' && Number.isFinite(value) ? value : null;
}

/**
 * Vertical rate in ft/min from a readsb-style aircraft row (readsb, tar1090,
 * adsb.lol): the barometric `baro_rate`, else the GNSS-sourced `geom_rate`
 * readsb sends instead when it has no barometric rate. A barometric 0 is kept.
 * Only a finite number counts; null when neither field has one.
 * @param {object|null|undefined} row
 * @returns {number|null}
 */
export function readAdsbVerticalRateFpm(row) {
  return rateField(row?.baro_rate) ?? rateField(row?.geom_rate);
}

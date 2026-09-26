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

export const LAYER_ID = 'local-adsb';
export const LAYER_NAME = 'Local ADS-B';
export const LAYER_SOURCE = 'RTL-SDR · WebUSB';
/** Distinct from the public Flights palette so both can be drawn together. */
export const LOCAL_ADSB_COLOR = '#ff4fd8';
/** Ring drawn around 978 MHz UAT aircraft: same magenta family, lighter. */
export const LOCAL_ADSB_UAT_RING_COLOR = '#ffb3ef';
export const ENTITY_PREFIX = `${LAYER_ID}:`;
/** Re-evaluate marker freshness and the card's position age this often. */
export const LOCAL_ADSB_TICK_MS = 1_000;
/** Coalesce receiver bursts into at most one scene sync per interval. */
export const LOCAL_ADSB_SYNC_MS = 200;
export const HEARD_BY_RECEIVER = 'Heard by your receiver';
export const BAND_LABELS = Object.freeze({
  1090: '1090 MHz',
  978: '978 MHz UAT',
});
export const SOURCE_LABELS = Object.freeze({
  webusb: 'browser SDR',
  feed: 'decoder feed',
});

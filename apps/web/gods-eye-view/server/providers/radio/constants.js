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

export const RADIO_DIRECTORY_CACHE_MS = 45 * 60 * 1000;
export const RADIO_DIRECTORY_STALE_MS = 7 * 24 * 60 * 60 * 1000;
export const RADIO_MIRROR_CACHE_MS = 6 * 60 * 60 * 1000;
export const RADIO_FETCH_TIMEOUT_MS = 12_000;
export const RADIO_RESPONSE_MAX_BYTES = 4 * 1024 * 1024;
export const RADIO_DIRECTORY_LIMIT = 750;
export const RADIO_CATALOG_MIN_SUCCESSFUL_QUERIES = 5;
export const RADIO_CATALOG_HEALTHY_MIN_STATIONS = Math.ceil(
  RADIO_DIRECTORY_LIMIT / 2,
);
export const RADIO_USER_AGENT =
  'GodsEyeView/1.0 (Radio Browser directory client)';
export { RADIO_UUID_RE } from '../../../src/sources/radioBrowser.js';
export const RADIO_FALLBACK_MIRRORS = Object.freeze([
  'https://de1.api.radio-browser.info',
  'https://de2.api.radio-browser.info',
  'https://nl1.api.radio-browser.info',
]);

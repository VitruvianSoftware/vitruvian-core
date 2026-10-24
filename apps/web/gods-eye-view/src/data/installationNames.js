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

import { msg } from '../i18n/marker.js';

/**
 * English names for installations without a mapped name. Data keeps them
 * English (server, AI tools, voice context); classLabel.js and
 * militaryAwarenessEngine.js translate them.
 */

/** Name of an unnamed feature, by installation class. */
export const UNNAMED_INSTALLATION_LABEL_BY_CLASS = Object.freeze({
  airfield: msg('Military airfield'),
  naval_base: msg('Naval base'),
  range: msg('Firing range'),
  military_land: msg('Military land'),
});

/** Name of an unnamed feature without a usable class. */
export const UNNAMED_INSTALLATION_FALLBACK = msg('Mapped installation');

/** Name of a military polygon the names pack has not named. */
export const UNNAMED_MILITARY_AREA = msg('Military area');

/** Every name above, for the display to translate. */
export const UNNAMED_PLACE_NAMES = Object.freeze([
  ...Object.values(UNNAMED_INSTALLATION_LABEL_BY_CLASS),
  UNNAMED_INSTALLATION_FALLBACK,
  UNNAMED_MILITARY_AREA,
]);

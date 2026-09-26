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

import { keySetupRequirement } from '../keySetupCore.mjs';
/**
 * Why Google 3D is unavailable, phrased so the tooltip and toast recommend the
 * RIGHT fix. With no credentials the fix is a key (or the ion route); with a
 * key or ion token configured, the tileset failed for another reason —
 * restrictions, quota, an EEA-billed key, or the network — and telling the
 * user to add a key they already added is the wrong advice.
 * @param {boolean} hasCredentials
 * @returns {string}
 */
export function photorealUnavailableReason(hasCredentials) {
  if (hasCredentials)
    return "Google 3D tiles unavailable — check the key's API restrictions, quota, or network";
  return `${keySetupRequirement('google-maps')} — or a Cesium ion token for the ion-hosted route`;
}

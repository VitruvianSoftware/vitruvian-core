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

import { FLEET_MODEL_POLICY } from '../../layers/flights/policy.js';

/**
 * The fleet-model service the Vessels, Transit and Rail layers draw their 3D
 * models with: the Flights layer's DISPLAY-rail 3D preference
 * (`{ models3d, models3dMode }`), the aircraft layers' icon-to-model rules,
 * and the resolver the fleet set's files are fetched through.
 * @param {{display?: (() => object|null)|null,
 *   resolveAsset?: (url: string) => string}} [options]
 * @returns {object|null} Null without a display preference (no models).
 */
export function fleetModelServices({
  display = null,
  resolveAsset = (url) =>
    `${import.meta.env?.BASE_URL || '/'}${url.replace(/^\//, '')}`,
} = {}) {
  if (!display) return null;
  return Object.freeze({ display, policy: FLEET_MODEL_POLICY, resolveAsset });
}

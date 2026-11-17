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

import { toLonLatH } from '../../geo/ellipsoid.js';
import { canvasOf, findCamera, findQuery } from '../../render/rendererOf.js';
import { viewAreaRadiusKm } from './viewArea.js';

/**
 * The area a viewer is looking at, as `{ lat, lon, radiusKm }`: centered on
 * the point in the middle of the screen (or below the camera when the middle
 * shows sky), sized by the camera's height. Null for a view that wants every
 * vessel.
 */
export function vesselViewArea(viewer) {
  const pose = findCamera(viewer)?.pose();
  const radiusKm = viewAreaRadiusKm(pose?.height);
  if (radiusKm == null) return null;
  let { lat, lon } = pose;
  const canvas = canvasOf(viewer);
  if (canvas?.clientWidth && canvas?.clientHeight) {
    try {
      const hit = findQuery(viewer)?.pickEllipsoid(
        canvas.clientWidth / 2,
        canvas.clientHeight / 2,
      );
      const center = hit ? toLonLatH(hit) : null;
      if (center) ({ lat, lon } = center);
    } catch {
      /* the camera position stands in */
    }
  }
  if (!Number.isFinite(lat) || !Number.isFinite(lon)) return null;
  return { lat, lon, radiusKm };
}

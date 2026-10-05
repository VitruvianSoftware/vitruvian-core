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

import * as Cesium from 'cesium';
import { viewAreaRadiusKm } from './viewArea.js';

/**
 * The area a viewer is looking at, as `{ lat, lon, radiusKm }`: centered on
 * the point in the middle of the screen (or below the camera when the middle
 * shows sky), sized by the camera's height. Null for a view that wants every
 * vessel.
 */
export function vesselViewArea(viewer) {
  const camera = viewer?.camera;
  const scene = viewer?.scene;
  const height = camera?.positionCartographic?.height;
  const radiusKm = viewAreaRadiusKm(height);
  if (radiusKm == null) return null;
  let center = camera.positionCartographic;
  const canvas = scene?.canvas;
  if (canvas?.clientWidth && canvas?.clientHeight) {
    try {
      const hit = camera.pickEllipsoid(
        new Cesium.Cartesian2(canvas.clientWidth / 2, canvas.clientHeight / 2),
        scene.globe?.ellipsoid,
      );
      if (hit) center = Cesium.Cartographic.fromCartesian(hit);
    } catch {
      /* the camera position stands in */
    }
  }
  const lat = Cesium.Math.toDegrees(center.latitude);
  const lon = Cesium.Math.toDegrees(center.longitude);
  if (!Number.isFinite(lat) || !Number.isFinite(lon)) return null;
  return { lat, lon, radiusKm };
}

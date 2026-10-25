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
import { resolvePickedContext } from '../data/pickedContext.js';
import { cameraPoseKey } from './pointerContext.js';
import * as defaultAnnotationResolver from '../annotations/annotationResolver.js';

/** "Around here" radius as a share of camera height, clamped to sane bounds. */
function pointerRadiusKm(cameraHeightM) {
  const heightKm = Number(cameraHeightM) / 1000;
  if (!Number.isFinite(heightKm) || heightKm <= 0) return 50;
  return Math.round(Math.min(400, Math.max(5, heightKm * 0.75)));
}

/**
 * The Cesium side of point-and-ask: one entity pick and one depth-aware world
 * pick at canvas CSS pixels. Called lazily by the pointer tracker (dwell and
 * snapshot only), never per mouse move.
 * @param {object} options
 * @param {object} options.viewer Cesium viewer.
 * @param {object} [options.dataManager] Layer lifecycle.
 * @param {Function} [options.pickWorldFromScreen] Normalized-pixel world pick.
 * @returns {(x: number, y: number) => {entity: object|null, ground: object|null, radiusKm: number}|null}
 */
export function createPointerPicker({
  viewer,
  dataManager = null,
  pickWorldFromScreen = defaultAnnotationResolver.pickWorldFromScreen,
}) {
  return function pickPointer(x, y) {
    const scene = viewer?.scene;
    const canvas = scene?.canvas;
    if (!scene || !canvas) return null;
    const width = canvas.clientWidth || canvas.width || 0;
    const height = canvas.clientHeight || canvas.height || 0;
    if (!width || !height) return null;
    let picked = null;
    try {
      picked = scene.pick(new Cesium.Cartesian2(x, y));
    } catch {
      picked = null;
    }
    const entity = resolvePickedContext(picked, { dataManager });
    let ground = null;
    try {
      const hit = pickWorldFromScreen(viewer, x / width, y / height);
      if (hit && Number.isFinite(hit.lat) && Number.isFinite(hit.lon))
        ground = {
          lat: hit.lat,
          lon: hit.lon,
          heightM: Number.isFinite(hit.height) ? Math.round(hit.height) : null,
        };
    } catch {
      ground = null;
    }
    return {
      entity,
      ground,
      radiusKm: pointerRadiusKm(viewer.camera?.positionCartographic?.height),
      cameraKey: cameraPoseKey(viewer),
    };
  };
}

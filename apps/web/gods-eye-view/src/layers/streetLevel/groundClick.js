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
import { GROUND_CLICK_MAX_HEIGHT_M } from './policy.js';
import { cameraHeightAboveGround } from './view.js';

/** Whether the camera is low enough for a click on the ground to mean a street. */
export function groundClickHeightOk(viewer) {
  if (!viewer?.camera?.positionCartographic) return false;
  return cameraHeightAboveGround(viewer) <= GROUND_CLICK_MAX_HEIGHT_M;
}

/**
 * A click on the map itself at street zoom opens the nearest image of the
 * active `groundClick` providers, without moving the camera. The height is
 * measured at the click, not read from the cached flag.
 * @param {{state: object, openNearest: Function, isAvailable: (entry: object) => boolean}} options
 * @returns {(screenPosition: {x: number, y: number}, picked?: object) => Promise<boolean>|false}
 */
export function createGroundClick({ state, openNearest, isAvailable }) {
  return function openAtGround(screenPosition, picked) {
    const scenePick = state.services.scenePick;
    if (!state.enabled || !state.viewer || !scenePick?.pickGroundPosition)
      return false;
    if (!scenePick.isSurfacePick(picked) || !groundClickHeightOk(state.viewer))
      return false;
    const providerIds = [...state.providers.values()]
      .filter(
        (entry) =>
          entry.on &&
          entry.def.groundClick &&
          entry.status?.configured &&
          isAvailable(entry),
      )
      .map((entry) => entry.def.id);
    if (!providerIds.length) return false;
    const position = scenePick.pickGroundPosition(state.viewer, screenPosition);
    const carto = position && Cesium.Cartographic.fromCartesian(position);
    if (!carto) return false;
    return openNearest(
      {
        lon: Cesium.Math.toDegrees(carto.longitude),
        lat: Cesium.Math.toDegrees(carto.latitude),
      },
      { providerIds, frame: false },
    );
  };
}

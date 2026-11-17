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

import { toRadians } from './geo/index.js';
import { cameraOf } from './render/rendererOf.js';

/**
 * The view the renderer starts from: the whole planet, looking straight
 * down, centred where Cesium's default view rectangle is.
 */
export const START_VIEW = Object.freeze({
  lon: -82.5,
  lat: 35,
  height: 23000000,
});

/**
 * Where this copy lands when the host passes no start view: Irvine, CA, from
 * above the city. One constant so the home city is a single edit (pinned by
 * camera.test.mjs).
 */
export const HOME_VIEW = Object.freeze({
  name: 'Irvine, CA',
  longitude: -117.8265,
  latitude: 33.6846,
});

export const HOME_START_VIEW = Object.freeze({
  lon: HOME_VIEW.longitude,
  lat: HOME_VIEW.latitude,
  height: 25000,
});

/**
 * Put the camera at a start view without a flight. A host may pass a city
 * (`{ lon, lat, height, heading?, pitch? }`, angles in degrees) instead of
 * the planet.
 */
export function applyStartView(viewer, view = START_VIEW) {
  const { lon, lat, height, heading = 0, pitch = -90 } = view;
  cameraOf(viewer).setView({
    destination: { lon, lat, height },
    orientation: {
      heading: toRadians(heading),
      pitch: toRadians(pitch),
      roll: 0,
    },
  });
}

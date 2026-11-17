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

/** Frame the complete finite footprint of a session-local file. */
import { guardCameraAboveGround } from '../cameraGroundGuard.js';
import { rangeForBoundingSphere } from '../data/cameraFraming.js';
import { cancelCameraArrival } from '../data/cameraArrival.js';
import { distance, fromDegrees, toLonLatH } from '../geo/index.js';
import { sphereFromPoints } from '../geo/sphere.js';
import { heightsOf } from '../queries/heights.js';
import { findCamera } from '../render/rendererOf.js';

/**
 * Fly synchronously to a footprint, `[lon, lat, height]` points (degrees,
 * metres) such as a file's (`importedDrawingPoints`); later navigation always
 * owns its camera. False when there is nothing to frame or no camera.
 */
export function flyToFootprint(
  viewer,
  points,
  { duration = 1.5, ground = null } = {},
) {
  if (!points?.length) return false;
  const camera = findCamera(viewer);
  if (!camera) return false;
  cancelCameraArrival(viewer);
  const positions = points.map(([lon, lat, height]) =>
    fromDegrees(lon, lat, height),
  );
  const sphere = sphereFromPoints(positions);
  const center = toLonLatH(sphere.center) || {
    lon: points[0][0],
    lat: points[0][1],
    height: 0,
  };
  const { lat, lon } = center;
  const terrain = viewer
    ? heightsOf(viewer).now({ lon, lat }, { against: 'terrain' })
    : null;
  const cached = ground?.cachedGroundFloor?.(lat, lon);
  const height =
    Number.isFinite(terrain) && terrain > 0
      ? terrain
      : Number.isFinite(cached)
        ? cached
        : Number.isFinite(terrain)
          ? terrain
          : 0;
  ground?.warmGroundFloor?.([{ lat, lon }]);
  const framed = {
    center: fromDegrees(lon, lat, Math.max(0, height, center.height)),
    radius: 0,
  };
  for (const position of positions)
    framed.radius = Math.max(framed.radius, distance(framed.center, position));
  camera.flyToBounds(framed, {
    offset: {
      heading: camera.pose().heading || 0,
      pitch: -Math.PI / 2,
      range: Math.max(800, rangeForBoundingSphere(viewer, framed.radius)),
    },
    durationS: duration,
    onComplete: () => guardCameraAboveGround(viewer, { lat, lon }),
  });
  return true;
}

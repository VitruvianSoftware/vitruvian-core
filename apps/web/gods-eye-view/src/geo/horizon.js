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

/**
 * @module geo/horizon
 * @description Whether a point is beyond the WGS84 ellipsoid's horizon from
 * an eye, by the default renderer's own test (`EllipsoidalOccluder`), so
 * code that culls by it agrees with what the renderer culls.
 */
import { WGS84 } from './ellipsoid.js';

/**
 * A horizon test from `eye` (ECEF): `isPointVisible(p)` is false for a
 * point the ellipsoid hides from it. `ellipsoid` (from `ellipsoidOf`) puts
 * the horizon on another surface, as the occluder takes one.
 */
export function horizonFrom(eye, ellipsoid) {
  // Anything but an ellipsoid (a map index, say) means WGS84.
  const o = (ellipsoid?.oneOverRadii ? ellipsoid : WGS84).oneOverRadii;
  const cx = eye.x * o.x;
  const cy = eye.y * o.y;
  const cz = eye.z * o.z;
  const limbSquared = cx * cx + cy * cy + cz * cz - 1;
  return {
    isPointVisible(p) {
      const tx = p.x * o.x - cx;
      const ty = p.y * o.y - cy;
      const tz = p.z * o.z - cz;
      const along = -(tx * cx + ty * cy + tz * cz);
      // Inside the ellipsoid the plane through the eye culls instead.
      const occluded =
        limbSquared < 0
          ? along > 0
          : along > limbSquared &&
            (along * along) / (tx * tx + ty * ty + tz * tz) > limbSquared;
      return !occluded;
    },
  };
}

/**
 * How high above the ellipsoid a point near sea level is judged, at least,
 * by a horizon test that lifts it: sea level sits at the geoid, below the
 * ellipsoid across much of the ocean, and would read as past the limb.
 */
export const HORIZON_LIFT_M = 12;

/**
 * `p` (ECEF) raised along its geocentric direction to at least `minHeightM`
 * above the ellipsoid, the point a lifted horizon test judges (as the default
 * renderer's GPU icons compute it).
 */
export function liftedForHorizon(p, minHeightM = HORIZON_LIFT_M) {
  const o = WGS84.oneOverRadii;
  const radius = Math.hypot(p.x, p.y, p.z);
  const scaled = Math.hypot(p.x * o.x, p.y * o.y, p.z * o.z);
  const height = radius * (1 - 1 / scaled);
  const k = Math.max(0, minHeightM - height) / radius;
  return { x: p.x + p.x * k, y: p.y + p.y * k, z: p.z + p.z * k };
}

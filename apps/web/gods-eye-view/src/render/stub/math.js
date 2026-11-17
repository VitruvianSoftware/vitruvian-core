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
 * @module render/stub/math
 * @description The maths the stub renderer poses its camera with: the shared
 * geodesy (`src/geo`) and the camera angle conventions of the contract
 * (heading clockwise from north, pitch negative looking down).
 *
 * The formulas follow the default renderer's, step for step, so the stub's
 * poses match its reference traces to floating-point noise.
 */
import {
  PI_OVER_TWO,
  TWO_PI,
  acosClamped,
  equalsEpsilon,
  rotate,
  vec,
  zeroToTwoPi,
} from '../../geo/index.js';

export * from '../../geo/index.js';

/** A contract `Position` (`Ecef` or `LonLatH`, degrees), as ECEF. */
export { positionToEcef as toEcef } from '../../geo/ellipsoid.js';

const EPSILON3 = 1e-3;
const EPSILON10 = 1e-10;

/**
 * The rotation the contract's heading, pitch and roll describe in a local
 * east-north-up frame, as its three columns: the direction, the left axis
 * and the up vector.
 */
export function headingPitchRollColumns(heading, pitch, roll) {
  const h = heading - PI_OVER_TWO;
  const rotateAll = (v) =>
    rotate(
      rotate(rotate(v, vec(1, 0, 0), roll), vec(0, 1, 0), -pitch),
      vec(0, 0, 1),
      -h,
    );
  return {
    direction: rotateAll(vec(1, 0, 0)),
    left: rotateAll(vec(0, 1, 0)),
    up: rotateAll(vec(0, 0, 1)),
  };
}

/** Heading of a local direction and up, radians clockwise from north. */
export function headingOf(direction, up) {
  const h = !equalsEpsilon(Math.abs(direction.z), 1.0, EPSILON3)
    ? Math.atan2(direction.y, direction.x) - PI_OVER_TWO
    : Math.atan2(up.y, up.x) - PI_OVER_TWO;
  return TWO_PI - zeroToTwoPi(h);
}

export const pitchOf = (direction) => PI_OVER_TWO - acosClamped(direction.z);

export function rollOf(direction, up, right) {
  if (equalsEpsilon(Math.abs(direction.z), 1.0, EPSILON3)) return 0;
  return zeroToTwoPi(Math.atan2(-right.z, up.z) + TWO_PI);
}

export { EPSILON10 };

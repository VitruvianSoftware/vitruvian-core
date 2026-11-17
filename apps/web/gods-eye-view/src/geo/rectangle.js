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
 * @module geo/rectangle
 * @description Geodetic rectangles `{west, south, east, north}` in radians,
 * as the default renderer measures them: a rectangle whose east is less
 * than its west crosses the antimeridian.
 */
import { TWO_PI, negativePiToPi } from './vector.js';

/** East-west extent, radians, across the antimeridian too. */
export function rectangleWidth({ west, east }) {
  return (east < west ? east + TWO_PI : east) - west;
}

/** North-south extent, radians. */
export const rectangleHeight = ({ south, north }) => north - south;

/** The middle `{lon, lat}`, radians, across the antimeridian too. */
export function rectangleCenter({ west, south, east, north }) {
  return {
    lon: negativePiToPi((west + (east < west ? east + TWO_PI : east)) / 2),
    lat: (south + north) / 2,
  };
}

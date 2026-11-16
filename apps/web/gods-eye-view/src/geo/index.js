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
 * @module geo
 * @description Cesium-free geodesy and vector maths: WGS84, ECEF and
 * geodetic conversions, east-north-up frames, quaternions, and the sun and
 * moon, a point along a geodesic and the ellipsoid's horizon. Plain numbers
 * and `{x, y, z}` objects only, so code that needs maths but not a renderer
 * does not import one.
 */
export * from './vector.js';
export * from './ellipsoid.js';
export * from './frames.js';
export * from './celestial.js';
export * from './julian.js';
export * from './quaternion.js';
export { geodesicAt } from './geodesic.js';
export { horizonFrom } from './horizon.js';

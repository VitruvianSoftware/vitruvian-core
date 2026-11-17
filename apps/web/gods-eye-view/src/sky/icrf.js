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
 * @module sky/icrf
 * @description The precise ICRF-to-fixed rotation, from the renderer that
 * has the tables for it (the Cesium adapter's starry sky provides it as it
 * loads, `src/render/cesium/starrySky.js`). Cesium-free: with none
 * provided, or before its tables load, it answers null and callers fall
 * back to `temeToPseudoFixed` (`src/geo/frames.js`).
 */

let provided = null;

/**
 * Provide the precise rotation; a later call replaces it.
 * @param {(ms: number) => ({x: object, y: object, z: object} | null)} axesAt
 */
export function provideIcrfToFixed(axesAt) {
  provided = axesAt;
}

/**
 * The precise ICRF-to-fixed rotation at `ms` (epoch milliseconds) as its
 * axes (the matrix's columns), or null while it is unknown.
 * @param {number} ms
 * @returns {{x: object, y: object, z: object} | null}
 */
export function icrfToFixedAxes(ms) {
  return provided ? provided(ms) : null;
}

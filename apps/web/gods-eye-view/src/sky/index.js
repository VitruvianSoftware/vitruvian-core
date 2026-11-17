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
 * @module sky
 * @description The sky background, Cesium-free: catalogue stars over a
 * soft Milky Way, both in ICRF/J2000, and the precise ICRF-to-fixed rotation
 * the Cesium renderer provides for the rest of the application.
 */

export {
  STAR_CATALOGUE_URL,
  MILKY_WAY_FACE_URLS,
  MILKY_WAY_INTENSITY,
} from './assets.js';
export {
  STAR_VERTEX_FLOATS,
  STAR_LIMIT_MAGNITUDE,
  buildStarVertices,
  raDecToUnitVector,
} from './stars.js';
export { provideIcrfToFixed, icrfToFixedAxes } from './icrf.js';

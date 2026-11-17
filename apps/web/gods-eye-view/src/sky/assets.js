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
 * @module sky/assets
 * @description The sky background's bundled data, Cesium-free: the
 * bright-star catalogue (`buildStarVertices` in `./stars.js` decodes it) and
 * the Milky Way glow's six cube faces, both in ICRF/J2000. See
 * `src/data/local_data/sky/README.md` for their sources and licences.
 */

/** The bright-star catalogue pack (`{ stars: [raDeg, decDeg, vmag, bv, …] }`). */
export const STAR_CATALOGUE_URL = new URL(
  '../data/local_data/sky/bright_stars.json',
  import.meta.url,
);

/**
 * The Milky Way's cube faces in the WebGL face order and layout: +X toward
 * the March equinox, +Z toward the north celestial pole, uploaded without
 * flipping.
 */
export const MILKY_WAY_FACE_URLS = Object.freeze({
  positiveX: new URL(
    '../data/local_data/sky/milkyway_px.webp',
    import.meta.url,
  ),
  negativeX: new URL(
    '../data/local_data/sky/milkyway_nx.webp',
    import.meta.url,
  ),
  positiveY: new URL(
    '../data/local_data/sky/milkyway_py.webp',
    import.meta.url,
  ),
  negativeY: new URL(
    '../data/local_data/sky/milkyway_ny.webp',
    import.meta.url,
  ),
  positiveZ: new URL(
    '../data/local_data/sky/milkyway_pz.webp',
    import.meta.url,
  ),
  negativeZ: new URL(
    '../data/local_data/sky/milkyway_nz.webp',
    import.meta.url,
  ),
});

/** The Milky Way glow's brightness at `SkySettings.milkyWay` 1: the stars carry the sky. */
export const MILKY_WAY_INTENSITY = 0.4;

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
 * Lighting options shared by every aircraft 3D model (Flights, Military
 * Flights, Local ADS-B).
 *
 * Cesium gives each Model a dynamic environment map: it renders the sky around
 * the model and reads the result back from the GPU (`readPixels`) to light it,
 * when the model is first placed and again when it moves more than 1 km, when
 * the scene's atmosphere settings change, or every scene hour under sunlight
 * lighting. Without it they are lit from Cesium's default spherical
 * harmonics. Measured 2026-10-24 (Intel Arc, Google 3D, ~150 models in the
 * scene): GPU per frame at rest 14.3-14.8 -> 12.1-12.5 ms.
 */
export const AIRCRAFT_ENVIRONMENT_MAP_OPTIONS = Object.freeze({
  enabled: false,
});

const HIGHLIGHT = Object.freeze({ mode: 'highlight' });
const FLAT = Object.freeze({ mode: 'mix', amount: 1 });

/**
 * How much of an emergency colour a model takes over its paint. Multiplying
 * by a saturated tint zeroes every channel the tint lacks: a cyan tint (no
 * red) draws a red helicopter black and a white Cessna flat cyan. Mixed in at
 * this share, the paint stays readable and the colour still marks the model.
 */
export const AIRCRAFT_MODEL_TINT_MIX = 0.3;

const TINTED = Object.freeze({ mode: 'mix', amount: AIRCRAFT_MODEL_TINT_MIX });

/**
 * How an aircraft model's colour meets its mesh, as a draw item's
 * `colorBlend`. White (no tint) multiplies (`highlight`), which draws the
 * mesh's own colours as built. An emergency colour is mixed in at
 * `AIRCRAFT_MODEL_TINT_MIX`, so it tints the mesh without hiding its paint.
 * The IR boost draws the model flat white instead (`mix` at 1, unlit).
 * @param {boolean} irBoost
 * @param {ArrayLike<number>|null} [tint] The model's RGBA tint, 0..1; white
 *   or none draws the mesh's own colours.
 * @returns {{mode: 'highlight'|'mix', amount?: number}}
 */
export function aircraftModelBlend(irBoost, tint = null) {
  if (irBoost) return FLAT;
  const white = !tint || (tint[0] >= 1 && tint[1] >= 1 && tint[2] >= 1);
  return white ? HIGHLIGHT : TINTED;
}

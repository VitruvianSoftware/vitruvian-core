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
 * lighting. Aircraft models take 94% of their surface from the class colour
 * (`colorBlendAmount`), so that lighting contributes little; without it they
 * are lit from Cesium's default spherical harmonics. Measured 2026-10-24
 * (Intel Arc, Google 3D, ~150 models in the scene): GPU per frame at rest
 * 14.3-14.8 -> 12.1-12.5 ms.
 */
export const AIRCRAFT_ENVIRONMENT_MAP_OPTIONS = Object.freeze({
  enabled: false,
});

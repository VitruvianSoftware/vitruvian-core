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

export const INFRARED_ALPHA_T0 = 0.4;
export const INFRARED_ALPHA_T1 = 0.7;

/** Return display pixels without changing RGB or the source RGBA bytes. */
export function infraredAlpha(rgba, mode = 'filtered') {
  const pixels = new Uint8ClampedArray(rgba);
  if (mode === 'full') return pixels;
  for (let i = 0; i < pixels.length; i += 4) {
    // Match Cesium's czm_srgbToLinear conversion in draped imagery.
    const linearMax =
      (Math.max(rgba[i], rgba[i + 1], rgba[i + 2]) / 255) ** 2.2;
    const t = Math.max(
      0,
      Math.min(
        1,
        (linearMax - INFRARED_ALPHA_T0) /
          (INFRARED_ALPHA_T1 - INFRARED_ALPHA_T0),
      ),
    );
    pixels[i + 3] = rgba[i + 3] * t * t * (3 - 2 * t);
  }
  return pixels;
}

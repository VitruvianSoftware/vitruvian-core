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
 * How a fleet model's draw item is turned, stretched and coloured
 * (`fleetModelInstances.js`): pure, no renderer, so it can be read without
 * the draw port.
 */

/** Every fleet GLB is nose -X: opposite the draw contract's heading 0. */
export const FLEET_HEADING_OFFSET_DEG = 180;

/**
 * A colour as the draw contract takes it: a CSS string or `[r, g, b, a]`
 * as given, `{red, green, blue, alpha}` as an array; null for none.
 */
export function fleetColor(color) {
  if (color === undefined || color === null) return null;
  if (typeof color === 'string' || Array.isArray(color)) return color;
  if (typeof color.red === 'number')
    return [color.red, color.green, color.blue, color.alpha ?? 1];
  return null;
}

/**
 * The per-axis stretch a fleet spec draws with on top of its length scale,
 * along the model's glTF axes (`x` its length, `y` its height, `z` its
 * beam), or undefined when it keeps its proportions.
 * @param {object} spec `fleetModelSpec`.
 * @returns {[number, number, number]|undefined}
 */
export function fleetAxisScale(spec) {
  const [length, beam, height] = spec?.scaleXYZ ?? [];
  if (!(length > 0) || (beam === length && height === length)) return;
  return [1, height / length, beam / length];
}

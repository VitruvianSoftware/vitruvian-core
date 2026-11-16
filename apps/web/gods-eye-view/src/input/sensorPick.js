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
 * @module sensorPick
 * @description Where a click lands in the pick buffer while a sensor style
 * distorts the picture. Picks read the scene before post-processing, so under
 * the thermal or surveillance shader the pixel the user clicked shows a
 * different spot of the scene: map it back through the shader's barrel
 * distortion and quantization first.
 */
import { styleStagesOf } from '../styles/styleStages.js';

const SENSOR_STYLES = ['thermal', 'surveillance'];

/**
 * The pick-buffer position for a screen click.
 * @param {object} host The scene object the styles are recorded on (the
 *   viewer the application's visual effects are made for).
 * @param {{x: number, y: number}} position CSS pixels on the canvas.
 * @param {{width: number, height: number, clientWidth: number,
 *   clientHeight: number}} canvas The canvas the scene draws in.
 * @returns {{x: number, y: number}} A new position; the click's own is left
 *   alone.
 */
export function sensorPickPosition(host, position, canvas) {
  const out = { x: position.x, y: position.y };
  const stages = styleStagesOf(host);
  if (!stages || !canvas) return out;
  for (const style of SENSOR_STYLES) {
    const stage = stages[style];
    if (!stage?.enabled) continue;
    const intensity = stage.uniforms.intensity;
    const w = canvas.clientWidth,
      h = canvas.clientHeight;
    let u = out.x / w,
      v = 1 - out.y / h;
    if (style === 'surveillance') {
      const x = u * 2 - 1,
        y = v * 2 - 1,
        r2 = x * x + y * y;
      const d = 1 + r2 * intensity * 0.25 + r2 * r2 * intensity * 0.075;
      u = (x * d + 1) / 2;
      v = (y * d + 1) / 2;
    }
    const grid = 1 + (stage.uniforms.pixelation - 1) * intensity;
    u +=
      ((Math.floor((u * canvas.width) / grid) * grid) / canvas.width - u) *
      intensity;
    v +=
      ((Math.floor((v * canvas.height) / grid) * grid) / canvas.height - v) *
      intensity;
    out.x = u * w;
    out.y = (1 - v) * h;
    return out;
  }
  return out;
}

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

const priorities = new WeakMap();

/** Scalar context, infrared, radar, then lightning: independent of enable order. */
export function orderWeatherImagery(collection, layer, priority) {
  priorities.set(layer, priority);
  if (typeof collection.raiseToTop !== 'function') return;
  const weather = [];
  for (let i = 0; i < collection.length; i++) {
    const item = collection.get(i);
    if (priorities.has(item)) weather.push(item);
  }
  const ordered = [...weather].sort(
    (a, b) => priorities.get(a) - priorities.get(b),
  );
  if (weather.every((item, i) => item === ordered[i])) return;
  for (const item of ordered) collection.raiseToTop(item);
}

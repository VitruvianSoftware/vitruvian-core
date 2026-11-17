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
 * The few interpolation helpers the launch paths and cameras share, written
 * as the default renderer writes them so the paths land on the same points.
 */

/** `p` to `q` by `t`. */
export const lerp = (p, q, t) => (1.0 - t) * p + t * q;

/** ECEF `start` to `end` by `t`, as a new point. */
export const lerpPoint = (start, end, t) => ({
  x: end.x * t + start.x * (1.0 - t),
  y: end.y * t + start.y * (1.0 - t),
  z: end.z * t + start.z * (1.0 - t),
});

/** `m` modulo `n`, in `n`'s sign. */
export function mod(m, n) {
  if (Math.sign(m) === Math.sign(n) && Math.abs(m) < Math.abs(n)) return m;
  return ((m % n) + n) % n;
}

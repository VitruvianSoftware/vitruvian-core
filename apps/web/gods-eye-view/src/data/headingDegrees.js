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

/** Normalize a heading into the [0, 360) range; 0 when it is not finite. */
export function normalizeHeading(value) {
  if (!Number.isFinite(value)) return 0;
  // Only a negative remainder takes the extra turn, so a positive bearing
  // keeps its precision (0.49999999999999 must not become 360.5).
  const remainder = value % 360;
  const wrapped = remainder < 0 ? remainder + 360 : remainder;
  return wrapped === 360 ? 0 : wrapped;
}

/**
 * Whole degrees for display, 0–359. 359.5° and above rounds to north (0),
 * and negative or multi-turn values wrap. Null when the value is not finite,
 * so each caller keeps its own placeholder.
 */
export function roundHeadingDegrees(value) {
  if (!Number.isFinite(value)) return null;
  return Math.round(normalizeHeading(value)) % 360;
}

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

/** Bound an upstream Retry-After delay (seconds or HTTP date). */
export function providerCooldownMs(response, now = Date.now()) {
  const raw = response?.headers?.get('retry-after')?.trim();
  const seconds = raw && /^\d+(?:\.\d+)?$/.test(raw) ? Number(raw) : NaN;
  const deadline = raw && !Number.isFinite(seconds) ? Date.parse(raw) : NaN;
  const delay = Number.isFinite(seconds)
    ? seconds * 1000
    : Number.isFinite(deadline)
      ? deadline - now
      : 60000;
  return Math.min(30 * 60000, Math.max(5000, delay));
}

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

/** A permanent session capability miss; clients must not schedule background retries. */
export function isUnavailableCapability(value) {
  return (
    value?.code === 'OVERPASS_NOT_CONFIGURED' ||
    value?.unavailable === true ||
    value?.retryable === false
  );
}

/** Preserve the server's explicit capability and cooldown fields without upstream text. */
export function sourceResponseError(body, response, message) {
  const seconds = Number(response?.headers?.get('retry-after'));
  return Object.assign(new Error(message), {
    code: body?.code,
    retryable: body?.retryable !== false,
    retryAfterMs: Math.max(
      Number(body?.retryAfterMs) || 0,
      Number.isFinite(seconds) ? seconds * 1000 : 0,
    ),
  });
}

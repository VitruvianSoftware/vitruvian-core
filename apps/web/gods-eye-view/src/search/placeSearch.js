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

/** A missing geocoder returns an unavailable outcome without making requests. */
export const unavailablePlaceSearch = Object.freeze({
  async geocode(_query, { signal } = {}) {
    signal?.throwIfAborted();
    return { place: null, answered: false };
  },
});

/**
 * Compose ordered geocoders into one bounded service. Each returns
 * { place: { lat, lng, name, label, types, viewport } | null, answered: boolean }.
 * Only definitive results are cached. Caller cancellation stops the whole chain.
 */
export function createPlaceSearch({
  providers,
  signal: lifetime,
  timeoutMs = 12_000,
  now = Date.now,
}) {
  const cache = new Map();
  return {
    async geocode(query, { bias = null, signal } = {}) {
      const combined = AbortSignal.any(
        [lifetime, signal, AbortSignal.timeout(timeoutMs)].filter(Boolean),
      );
      combined.throwIfAborted();
      const text = String(query ?? '').trim();
      if (!text) return { place: null, answered: true };
      const key = `${bias || ''}\n${text.toLowerCase()}`;
      const cached = cache.get(key);
      if (cached && cached.expires > now()) return cached.result;
      cache.delete(key);
      let result = { place: null, answered: providers.length > 0 };
      try {
        for (const [index, provider] of providers.entries()) {
          combined.throwIfAborted();
          const next = await provider.geocode(text, { bias, signal: combined });
          combined.throwIfAborted();
          result = {
            place: next.place,
            answered: Boolean(next.place) || (result.answered && next.answered),
          };
          if (result.place) {
            result.fallbackUsed = index > 0;
            break;
          }
        }
      } catch (error) {
        lifetime?.throwIfAborted();
        signal?.throwIfAborted();
        if (!combined.aborted) throw error;
        return { place: null, answered: false };
      }
      combined.throwIfAborted();
      if (result.answered) {
        cache.set(key, {
          result,
          expires: now() + (result.place ? 300_000 : 30_000),
        });
        while (cache.size > 64) cache.delete(cache.keys().next().value);
      }
      return result;
    },
  };
}

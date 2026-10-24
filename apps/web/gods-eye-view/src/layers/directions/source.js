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

// A source module (no browser globals, see check:boundaries), so no i18n
// import: failures stay English here and the layer translates them on show.
const msg = (text) => text;

/** Build the existing route-proxy query from geographic endpoints. */
export function directionsRequestUrl(mode, a, b) {
  const coords = `${a.lon.toFixed(6)},${a.lat.toFixed(6)};${b.lon.toFixed(6)},${b.lat.toFixed(6)}`;
  return `/api/route?profile=${encodeURIComponent(mode)}&coords=${encodeURIComponent(coords)}&steps=1`;
}

/** Acquire route records using caller-owned transport and an optional endpoint. */
export function createDirectionsSource({
  fetchImpl = (...args) => globalThis.fetch(...args),
  endpoint = '/api/route',
} = {}) {
  return {
    async getRoute({ mode, a, b }, { signal } = {}) {
      signal?.throwIfAborted();
      const query = directionsRequestUrl(mode, a, b).split('?')[1];
      const response = await fetchImpl(`${endpoint}?${query}`, {
        signal,
        headers: { Accept: 'application/json' },
      });
      const payload = await response.json();
      signal?.throwIfAborted();
      // Failures keep their English message and carry the HTTP status and the
      // server's refusal text, so the layer can show them in the language.
      if (response.status === 429) {
        const refusal =
          typeof payload?.error === 'string' && payload.error
            ? payload.error
            : null;
        throw Object.assign(
          new Error(
            refusal
              ? `${refusal} — try again in a moment`
              : msg('Routing is rate limited — try again in a moment'),
          ),
          { status: 429, refusal },
        );
      }
      if (!response.ok && !payload?.error)
        throw Object.assign(
          new Error(`Routing unavailable (HTTP ${response.status})`),
          { status: response.status },
        );
      return payload;
    },
  };
}

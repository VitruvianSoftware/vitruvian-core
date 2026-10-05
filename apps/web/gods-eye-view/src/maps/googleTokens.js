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
 * Short-lived Google access tokens the app's server may offer in place of a
 * browser key. A server that offers them answers GET GOOGLE_TOKEN_PATH with
 * `{ accessToken, expiresAt }` (expiresAt in epoch milliseconds); any other
 * answer means it does not, and the app carries on without them.
 */
export const GOOGLE_TOKEN_PATH = '/api/google/tiles-token';

/** Renew a token this long before it expires. */
const RENEW_EARLY_MS = 60_000;

function parseToken(data, now) {
  const accessToken = data?.accessToken;
  const expiresAt = Number(data?.expiresAt);
  if (typeof accessToken !== 'string' || accessToken.length === 0) return null;
  if (!Number.isFinite(expiresAt) || expiresAt <= now) return null;
  return { accessToken, expiresAt };
}

/**
 * A source of tokens from the app's server. `token()` resolves the current
 * token, renewing it shortly before it expires; `token({ replacing })`
 * renews only if `replacing` is still the current token, so many tile
 * requests rejected for the same expired token renew it once. Resolves null
 * when the server does not offer tokens.
 */
export function createGoogleTokenSource({
  fetchImpl = (...args) => fetch(...args),
  url = GOOGLE_TOKEN_PATH,
  now = () => Date.now(),
} = {}) {
  let current = null;
  let pending = null;

  async function request() {
    try {
      const response = await fetchImpl(url, {
        headers: { Accept: 'application/json' },
        cache: 'no-store',
      });
      if (!response.ok) return null;
      return parseToken(await response.json(), now());
    } catch {
      return null;
    }
  }

  return {
    async token({ replacing } = {}) {
      const usable =
        current &&
        current.expiresAt - RENEW_EARLY_MS > now() &&
        (replacing === undefined || current.accessToken !== replacing);
      if (usable) return current.accessToken;
      pending ??= request().finally(() => {
        pending = null;
      });
      current = await pending;
      return current?.accessToken ?? null;
    },
  };
}

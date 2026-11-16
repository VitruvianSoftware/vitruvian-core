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
 * Keep browser QA off third-party aircraft photo services.
 *
 * Tracking a civil flight asks Planespotters for the aircraft's photo. QA
 * runs track synthetic hexes, so a real request only adds a third-party
 * dependency and, when the service refuses a headless browser, a console
 * error that fails the "no console errors" checks. Every photo lookup is
 * answered with no photos instead, without leaving the browser.
 */

/** Origin of the aircraft photo lookup. */
export const PLANESPOTTERS_ORIGIN = 'https://api.planespotters.net';

/** The answer every stubbed lookup gets: no photos for this aircraft. */
export const PLANESPOTTERS_EMPTY_BODY = JSON.stringify({ photos: [] });

/** Whether a URL is a photo lookup the stub answers. */
export function isPlanespottersRequest(url) {
  try {
    return new URL(String(url)).origin === PLANESPOTTERS_ORIGIN;
  } catch {
    return false;
  }
}

/**
 * Answer an intercepted photo lookup from a page that already uses request
 * interception. Returns false for any other request, which the caller
 * handles as before.
 * @param {import('puppeteer').HTTPRequest} request
 * @returns {boolean} Whether the request was answered.
 */
export function respondToPlanespotters(request) {
  if (!isPlanespottersRequest(request.url())) return false;
  request.respond({
    status: 200,
    contentType: 'application/json',
    headers: { 'Access-Control-Allow-Origin': '*' },
    body: PLANESPOTTERS_EMPTY_BODY,
  });
  return true;
}

/**
 * Stub photo lookups in a page that does not intercept requests: wraps
 * `fetch` before any app code runs, so a lookup never reaches the network.
 * Composes with other `fetch` shims in either order.
 * @param {import('puppeteer').Page} page
 * @returns {Promise<void>}
 */
export async function stubPlanespotters(page) {
  await page.evaluateOnNewDocument(
    (origin, body) => {
      const original = window.fetch.bind(window);
      window.fetch = (input, init) => {
        const href =
          typeof input === 'string' ? input : input?.url || String(input);
        let target = '';
        try {
          target = new URL(href, location.href).origin;
        } catch {
          /* not a URL */
        }
        if (target === origin) {
          return Promise.resolve(
            new Response(body, {
              status: 200,
              headers: { 'Content-Type': 'application/json' },
            }),
          );
        }
        return original(input, init);
      };
    },
    PLANESPOTTERS_ORIGIN,
    PLANESPOTTERS_EMPTY_BODY,
  );
}

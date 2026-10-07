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

import { sameSiteGated } from '../common/same-site.js';
import { makeRateLimiter, clientKey } from '../common/rate-limit.js';
import { fetchTile, TileRequestError, TileUpstreamError } from './tiles.js';
import { mapillaryToken, TILE_ROUTE_MAX_PER_MIN } from './constants.js';

function sendJson(res, status, payload) {
  res.statusCode = status;
  res.setHeader('Content-Type', 'application/json; charset=utf-8');
  res.setHeader('Cache-Control', 'no-store');
  res.end(JSON.stringify(payload));
}

/** GET /api/mapillary/status — whether a token is configured, never its value. */
function handleStatus(req, res) {
  if (req.method !== 'GET')
    return sendJson(res, 405, { error: 'Method not allowed' });
  sendJson(res, 200, { configured: Boolean(mapillaryToken()) });
}

/** GET /api/mapillary/tiles/coverage/{z}/{x}/{y} — cached protobuf tile. */
async function handleTile(req, res, allow) {
  if (req.method !== 'GET')
    return sendJson(res, 405, { error: 'Method not allowed' });
  if (!allow(clientKey(req))) {
    res.setHeader('Retry-After', '5');
    return sendJson(res, 429, {
      error: 'Too many tile requests',
      retryAfter: 5,
    });
  }
  const match = /^\/(coverage)\/(\d{1,2})\/(\d{1,6})\/(\d{1,6})$/.exec(
    (req.url || '').split('?')[0],
  );
  if (!match)
    return sendJson(res, 400, {
      error: 'Tile path must be /coverage/{z}/{x}/{y}',
    });
  if (!mapillaryToken())
    return sendJson(res, 503, { error: 'no_key', keyRequired: true });
  const abandoned = new AbortController();
  req.on?.('aborted', () => abandoned.abort());
  res.on?.('close', () => abandoned.abort());
  try {
    const { bytes, source } = await fetchTile(
      { layer: match[1], z: match[2], x: match[3], y: match[4] },
      { signal: abandoned.signal },
    );
    if (res.writableEnded) return;
    res.statusCode = bytes.length ? 200 : 204;
    res.setHeader('Content-Type', 'application/x-protobuf');
    res.setHeader('Cache-Control', 'public, max-age=3600');
    res.setHeader('X-Gev-Cache', source);
    res.end(bytes.length ? bytes : undefined);
  } catch (error) {
    if (res.writableEnded || abandoned.signal.aborted) return;
    if (error instanceof TileRequestError)
      return sendJson(res, error.status, { error: error.message });
    if (error instanceof TileUpstreamError) {
      // A rejected token is a key problem the panel can name, not a fault.
      if (error.keyRejected)
        return sendJson(res, 403, {
          error: 'Mapillary rejected the access token',
          keyRejected: true,
        });
      if (error.status === 429) {
        const retryAfter = error.retryAfterSec || 60;
        res.setHeader('Retry-After', String(retryAfter));
        return sendJson(res, 429, {
          error: 'Mapillary is rate-limiting tile requests',
          retryAfter,
        });
      }
      // An upstream 400 must not read as a malformed request to this proxy.
      return sendJson(res, 502, { error: error.message });
    }
    sendJson(res, 502, { error: error?.message || 'Tile fetch failed' });
  }
}

/**
 * Attach the Mapillary routes. Both refuse cross-site requests so another page
 * cannot spend the token or provoke a 429 that holds every tile miss.
 */
export function installMapillaryRoutes(middlewares) {
  const allow = makeRateLimiter({
    windowMs: 60_000,
    max: TILE_ROUTE_MAX_PER_MIN,
    globalMax: TILE_ROUTE_MAX_PER_MIN * 4,
  });
  middlewares.use('/api/mapillary/status', sameSiteGated(handleStatus));
  middlewares.use(
    '/api/mapillary/tiles',
    sameSiteGated((req, res) => handleTile(req, res, allow)),
  );
}

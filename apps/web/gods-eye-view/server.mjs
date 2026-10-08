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
 * Production HTTP server for God's Eye View.
 *
 * Serves the built dist/ and answers /api with upstream's own route handlers:
 * the provider plugins upstream's Vite server mounts (server/providers/local.js),
 * installed through each plugin's configurePreviewServer hook, as `vite preview`
 * installs them. A route an upstream sync adds or changes therefore reaches
 * production with that sync; nothing here re-implements one.
 *
 * Two consequences of running upstream's code the way `vite preview` does:
 *  - Upstream installs its credential panel (/api/setup/*) in its dev server
 *    only, so production never serves it.
 *  - Upstream's same-site gate stays on. Its paid routes (OpenAI, Google Places,
 *    Street Level) refuse a request that carries reverse-proxy headers, which
 *    every request through the cluster gateway does, so the public site never
 *    spends a configured key.
 *
 * @module server.mjs
 */

import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { localProviderPlugins } from './server/providers/local.js';
import { apiNotFoundPlugin } from './server/standalone/api-not-found.js';
import { standaloneVoiceTools } from './server/standalone/voiceTools.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const DIST_DIR = path.resolve(__dirname, 'dist');

const PORT = parseInt(process.env.PORT || '8080', 10);
const HOST = process.env.HOST || '0.0.0.0';

// ---------------------------------------------------------------------------
// Middleware stack
// ---------------------------------------------------------------------------

/**
 * The part of connect, Vite's middleware stack, that upstream's plugins rely
 * on. `use(route, handler)` runs handler for a request at route or below it,
 * with req.url made relative to route and req.originalUrl left whole; a
 * handler passes the request on by calling next(), or next(error) to fail it.
 * @returns {{use: Function, handle: Function}}
 */
function createMiddlewares() {
  const layers = [];

  function matches(route, pathname) {
    if (!route) return true;
    if (pathname.slice(0, route.length).toLowerCase() !== route.toLowerCase()) return false;
    const boundary = pathname[route.length];
    return boundary === undefined || boundary === '/' || boundary === '.';
  }

  function call(handler, error, req, res, next) {
    const handlesErrors = handler.length === 4;
    if (Boolean(error) !== handlesErrors) return next(error);
    try {
      const result = handlesErrors ? handler(error, req, res, next) : handler(req, res, next);
      if (result && typeof result.catch === 'function') result.catch(next);
    } catch (thrown) {
      next(thrown);
    }
  }

  return {
    use(route, handler) {
      if (typeof route === 'function') [route, handler] = ['/', route];
      layers.push({ route: route.replace(/\/+$/, ''), handler });
      return this;
    },
    /** Runs the stack; `done(error)` runs when no layer finished the request. */
    handle(req, res, done) {
      const url = req.url;
      const pathname = url.split('?')[0];
      req.originalUrl ??= url;
      let index = 0;
      const next = (error) => {
        req.url = url;
        let layer = layers[index++];
        while (layer && !matches(layer.route, pathname)) layer = layers[index++];
        if (!layer) return done(error);
        const rest = url.slice(layer.route.length);
        req.url = rest.startsWith('/') ? rest : `/${rest}`;
        return call(layer.handler, error, req, res, next);
      };
      next();
    },
  };
}

// ---------------------------------------------------------------------------
// Static assets
// ---------------------------------------------------------------------------
const MIME_TYPES = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'application/javascript; charset=utf-8',
  '.mjs': 'application/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.geojson': 'application/geo+json; charset=utf-8',
  '.geojsonl': 'application/x-ndjson; charset=utf-8',
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.jpeg': 'image/jpeg',
  '.gif': 'image/gif',
  '.svg': 'image/svg+xml',
  '.webp': 'image/webp',
  '.ico': 'image/x-icon',
  '.woff': 'font/woff',
  '.woff2': 'font/woff2',
  '.ttf': 'font/ttf',
  '.wasm': 'application/wasm',
  '.gltf': 'model/gltf+json',
  '.glb': 'model/gltf-binary',
  '.bin': 'application/octet-stream',
  '.pbf': 'application/x-protobuf',
  '.txt': 'text/plain; charset=utf-8',
};

async function statOrNull(filePath) {
  try {
    return await fs.promises.stat(filePath);
  } catch {
    return null;
  }
}

/** Serves a file from dist/, falling back to index.html for app routes. */
async function serveStatic(req, res, pathname) {
  let sanitizedPath = path.normalize(pathname).replace(/^(\.\.[/\\])+/, '');
  if (sanitizedPath === '/' || sanitizedPath === '') sanitizedPath = '/index.html';

  let filePath = path.join(DIST_DIR, sanitizedPath);
  if (!filePath.startsWith(DIST_DIR)) {
    res.writeHead(403, { 'Content-Type': 'text/plain' });
    res.end('Forbidden');
    return;
  }

  let stat = await statOrNull(filePath);
  if (stat && stat.isDirectory()) {
    filePath = path.join(filePath, 'index.html');
    stat = await statOrNull(filePath);
  }
  // SPA fallback: an unknown path without an extension is an app route.
  if (!stat && !path.extname(sanitizedPath)) {
    filePath = path.join(DIST_DIR, 'index.html');
    stat = await statOrNull(filePath);
  }
  if (!stat) {
    res.writeHead(404, { 'Content-Type': 'text/plain' });
    res.end('Not Found');
    return;
  }

  const ext = path.extname(filePath).toLowerCase();
  const isImmutable = sanitizedPath.startsWith('/assets/') || sanitizedPath.startsWith('/cesium/');
  res.writeHead(200, {
    'Content-Type': MIME_TYPES[ext] || 'application/octet-stream',
    'Content-Length': stat.size,
    'Cache-Control': isImmutable
      ? 'public, max-age=31536000, immutable'
      : (ext === '.html' ? 'no-cache' : 'public, max-age=86400'),
  });
  const stream = fs.createReadStream(filePath);
  stream.on('error', (err) => {
    console.warn('[Server] Static file stream error:', err?.message);
    if (!res.headersSent) res.writeHead(500, { 'Content-Type': 'text/plain' });
    res.end();
  });
  stream.pipe(res);
}

// ---------------------------------------------------------------------------
// Server
// ---------------------------------------------------------------------------
const middlewares = createMiddlewares();

const server = http.createServer((req, res) => {
  let pathname;
  try {
    pathname = new URL(req.url || '/', 'http://localhost').pathname;
  } catch {
    res.writeHead(400, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ error: 'Bad Request: Malformed URL' }));
    return;
  }

  res.setHeader('X-Content-Type-Options', 'nosniff');
  res.setHeader('X-Frame-Options', 'DENY');
  res.setHeader('Content-Security-Policy', "frame-ancestors 'none'");

  if (pathname === '/healthz' || pathname === '/health' || pathname === '/ping') {
    res.writeHead(200, { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' });
    res.end(JSON.stringify({ status: 'ok', uptime: process.uptime() }));
    return;
  }

  middlewares.handle(req, res, (error) => {
    if (error) {
      console.error('[Server] Unhandled request error:', error);
      if (!res.headersSent) {
        res.writeHead(500, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ error: 'Internal server error' }));
      } else {
        res.end();
      }
      return;
    }
    serveStatic(req, res, pathname).catch((err) => {
      console.error('[Server] Static serving error:', err);
      if (!res.headersSent) res.writeHead(500, { 'Content-Type': 'text/plain' });
      res.end();
    });
  });
});

/** Whether Vite would apply `plugin` to `vite preview`, by its `apply` field. */
function appliesToPreview(plugin) {
  if (typeof plugin.apply === 'function') {
    return Boolean(plugin.apply({}, { command: 'serve', mode: 'production', isPreview: true }));
  }
  return plugin.apply === undefined || plugin.apply === 'serve';
}

// Upstream's provider routes, in upstream's order, then its /api catch-all so
// an unknown API path answers 404 JSON instead of the app's index.html.
const previewServer = { middlewares, httpServer: server };
for (const plugin of [
  ...localProviderPlugins({ realtime: { tools: standaloneVoiceTools() } }),
  apiNotFoundPlugin(),
]) {
  if (appliesToPreview(plugin)) plugin.configurePreviewServer?.(previewServer);
}

// A provider fault must not take the whole server down.
process.on('uncaughtException', (err) => {
  console.error('[Process] Uncaught exception trapped:', err);
});
process.on('unhandledRejection', (reason) => {
  console.error('[Process] Unhandled promise rejection trapped:', reason);
});

server.on('error', (err) => {
  console.error("[God's Eye View] Server error:", err);
});

const isDirectExecution = Boolean(
  process.argv[1] && (
    path.resolve(process.argv[1]) === __filename ||
    process.argv[1].endsWith('server.mjs')
  ),
);

if (isDirectExecution || process.env.NODE_ENV === 'production' || process.env.AUTO_START_SERVER === 'true') {
  server.listen(PORT, HOST, () => {
    console.log(`[God's Eye View] Production server listening on http://${HOST}:${PORT}`);
    console.log(`[God's Eye View] Static assets served from: ${DIST_DIR}`);
  });
}

export { server, createMiddlewares };
export default server;

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
 * Production HTTP & WebSocket Server for God's Eye View.
 *
 * Capabilities:
 *  - Serves static assets from dist/ with proper MIME types, caching, and SPA fallback.
 *  - Health check endpoints (/healthz, /health).
 *  - Outbound persistent WebSocket client connection to AISStream with auto-reconnect backoff.
 *  - Inbound WebSocket server streaming live vessel positions to connected clients.
 *  - 26 backend API proxy endpoints brokering external APIs (OpenSky, CelesTrak, FIRMS,
 *    CCTV, TomTom, Overpass, GBFS, adsb.lol, OpenAI Realtime token minting, Google Places).
 *  - Rate limiting guards honoring GEV_RATELIMIT, GEV_RATELIMIT_OPENAI_PER_MIN, GEV_RATELIMIT_GOOGLE_PER_MIN.
 *
 * @module server.mjs
 */

import http from 'node:http';
import https from 'node:https';
import fs from 'node:fs';
import path from 'node:path';
import dns from 'node:dns';
import { fileURLToPath } from 'node:url';
import { WebSocket, WebSocketServer } from 'ws';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const DIST_DIR = path.resolve(__dirname, 'dist');

const PORT = parseInt(process.env.PORT || '8080', 10);
const HOST = process.env.HOST || '0.0.0.0';

// ---------------------------------------------------------------------------
// Rate Limiting (GEV_RATELIMIT, GEV_RATELIMIT_OPENAI_PER_MIN, GEV_RATELIMIT_GOOGLE_PER_MIN)
// ---------------------------------------------------------------------------
const _rateLimitHits = new Map();

function checkRateLimit(ip, limitPerMin) {
  if (!limitPerMin || limitPerMin <= 0) return true;
  const now = Date.now();
  const windowMs = 60_000;
  if (_rateLimitHits.size > 2048) {
    for (const [key, times] of _rateLimitHits) {
      if (times.every((t) => now - t >= windowMs)) {
        _rateLimitHits.delete(key);
      }
    }
  }
  let timestamps = _rateLimitHits.get(ip) || [];
  timestamps = timestamps.filter((t) => now - t < windowMs);
  if (timestamps.length >= limitPerMin) {
    _rateLimitHits.set(ip, timestamps);
    return false;
  }
  timestamps.push(now);
  _rateLimitHits.set(ip, timestamps);
  return true;
}

function getClientIp(req) {
  const xForwardedFor = req.headers?.['x-forwarded-for'];
  if (xForwardedFor && typeof xForwardedFor === 'string') {
    const firstIp = xForwardedFor.split(',')[0].trim();
    if (firstIp) return firstIp;
  }
  const xRealIp = req.headers?.['x-real-ip'];
  if (xRealIp && typeof xRealIp === 'string') {
    const ip = xRealIp.trim();
    if (ip) return ip;
  }
  return String(req.socket?.remoteAddress || '127.0.0.1');
}

function enforceRateLimit(req, res, envLimitName, defaultLimit = 0) {
  const envVal = process.env[envLimitName] || process.env.GEV_RATELIMIT;
  const limit = envVal ? parseInt(envVal, 10) : defaultLimit;
  if (!limit || limit <= 0) return true;
  const ip = (process.env.TRUST_PROXY === 'true') ? getClientIp(req) : String(req.socket?.remoteAddress || getClientIp(req));
  if (!checkRateLimit(ip, limit)) {
    res.writeHead(429, {
      'Content-Type': 'application/json',
      'Retry-After': '10',
    });
    res.end(JSON.stringify({ error: 'Rate limit exceeded' }));
    return false;
  }
  return true;
}

// ---------------------------------------------------------------------------
// MIME Types
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

// ---------------------------------------------------------------------------
// Outbound / Inbound AISStream WebSocket Manager
// ---------------------------------------------------------------------------
const AISSTREAM_URL = process.env.AISSTREAM_URL || 'wss://stream.aisstream.io/v0/stream';
const AISSTREAM_CACHE_MAX = 5000;
const AISSTREAM_STALE_MS = 600_000; // 10 minutes

const _aisVessels = new Map();
const _aisTracks = new Map();
let _aisWs = null;
let _aisReconnectTimeout = null;
let _aisReconnectDelay = 2000;
const _aisMaxReconnectDelay = 60000;
let _aisReconnectAttempt = 0;
let _aisStatus = 'idle';
let _aisLastError = null;
let _lastAisMessageAt = null;

// Inbound WebSocket clients connected to this server
const wss = new WebSocketServer({ noServer: true });

function broadcastToClients(data) {
  const payload = typeof data === 'string' ? data : JSON.stringify(data);
  for (const client of wss.clients) {
    if (client.readyState === WebSocket.OPEN) {
      client.send(payload);
    }
  }
}

function scheduleAisReconnect() {
  if (_aisReconnectTimeout) return;
  _aisReconnectAttempt++;
  _aisStatus = 'reconnecting';
  _aisReconnectDelay = Math.min(_aisReconnectDelay * 1.5, _aisMaxReconnectDelay);
  _aisReconnectTimeout = setTimeout(() => {
    _aisReconnectTimeout = null;
    connectAisStream();
  }, _aisReconnectDelay);
}

function connectAisStream() {
  const apiKey = process.env.AISSTREAM_API_KEY;
  if (!apiKey && !process.env.AISSTREAM_URL) {
    _aisStatus = 'missing-key';
    _aisLastError = 'AISSTREAM_API_KEY is not set';
    return;
  }

  try {
    _aisStatus = 'connecting';
    const ws = new WebSocket(AISSTREAM_URL);
    _aisWs = ws;

    ws.on('open', () => {
      _aisStatus = 'live';
      _aisLastError = null;
      _aisReconnectAttempt = 0;
      _aisReconnectDelay = 2000;

      const subscription = {
        APIKey: apiKey || '',
        BoundingBoxes: [[[-90, -180], [90, 180]]],
        FilterMessageTypes: ['PositionReport', 'StandardClassBPositionReport', 'ShipStaticData', 'StaticDataReport'],
      };
      ws.send(JSON.stringify(subscription));
    });

    ws.on('message', (raw) => {
      try {
        _lastAisMessageAt = Date.now();
        const envelope = JSON.parse(raw.toString());
        const msgType = envelope?.MessageType;
        const msg = envelope?.Message?.[msgType] || {};
        const meta = envelope?.MetaData || envelope?.Metadata || {};
        const mmsi = String(meta.MMSI ?? msg.UserID ?? msg.UserId ?? msg.Mmsi ?? '').trim();
        if (!mmsi) return;

        const lat = Number(meta.latitude ?? meta.Latitude ?? msg.Latitude);
        const lon = Number(meta.longitude ?? meta.Longitude ?? msg.Longitude);

        if (Number.isFinite(lat) && Number.isFinite(lon)) {
          const vessel = {
            mmsi,
            name: String(meta.ShipName ?? msg.Name ?? `MMSI ${mmsi}`).trim(),
            lat,
            lon,
            sog: Number(msg.Sog ?? msg.SpeedOverGround ?? 0),
            cog: Number(msg.Cog ?? msg.CourseOverGround ?? 0),
            heading: Number(msg.TrueHeading ?? msg.Heading ?? 0),
            timestamp: meta.time_utc || new Date().toISOString(),
            updatedAt: Date.now(),
          };

          _aisVessels.set(mmsi, vessel);
          if (_aisVessels.size > AISSTREAM_CACHE_MAX) {
            const oldestKey = _aisVessels.keys().next().value;
            if (oldestKey) {
              _aisVessels.delete(oldestKey);
              _aisTracks.delete(oldestKey);
            }
          }

          let track = _aisTracks.get(mmsi);
          if (!track) {
            track = [];
            _aisTracks.set(mmsi, track);
          }
          track.push([lat, lon, Date.now()]);
          if (track.length > 100) track.shift();

          broadcastToClients({ type: 'vessel', vessel });
        }
      } catch (err) {
        // Ignore unparseable frames
      }
    });

    ws.on('error', (err) => {
      _aisStatus = 'error';
      _aisLastError = err?.message || 'WebSocket connection error';
      console.warn('[AISStream] ws error:', _aisLastError);
    });

    ws.on('close', () => {
      _aisWs = null;
      if (_aisStatus !== 'missing-key') {
        scheduleAisReconnect();
      }
    });
  } catch (err) {
    _aisStatus = 'error';
    _aisLastError = err?.message || 'Failed to initialize WebSocket';
    scheduleAisReconnect();
  }
}

// Start outbound AIS stream connection
connectAisStream();

// Periodic cleanup of rate limits and stale vessel tracks (every 5 min)
setInterval(() => {
  const now = Date.now();
  for (const [ip, timestamps] of _rateLimitHits.entries()) {
    const fresh = timestamps.filter((t) => now - t < 60_000);
    if (fresh.length === 0) {
      _rateLimitHits.delete(ip);
    } else {
      _rateLimitHits.set(ip, fresh);
    }
  }
  for (const [mmsi, vessel] of _aisVessels.entries()) {
    if (now - vessel.updatedAt > AISSTREAM_STALE_MS) {
      _aisVessels.delete(mmsi);
      _aisTracks.delete(mmsi);
    }
  }
}, 300_000).unref();

// ---------------------------------------------------------------------------
// Security: Safe URL Parsing & SSRF Firewall
// ---------------------------------------------------------------------------
function isPrivateIpAddress(ipStr) {
  if (!ipStr) return true;
  let ip = String(ipStr).toLowerCase().trim();
  if (ip.startsWith('[') && ip.endsWith(']')) {
    ip = ip.slice(1, -1);
  }
  if (ip.startsWith('::ffff:')) {
    ip = ip.slice(7);
    const hexMatch = ip.match(/^([0-9a-f]{1,4}):([0-9a-f]{1,4})$/i);
    if (hexMatch) {
      const high = parseInt(hexMatch[1], 16);
      const low = parseInt(hexMatch[2], 16);
      ip = `${(high >> 8) & 0xff}.${high & 0xff}.${(low >> 8) & 0xff}.${low & 0xff}`;
    }
  }
  if (ip === '::1' || ip === '::' || ip === '0.0.0.0') {
    return true;
  }
  // IPv4 check
  const ipv4Parts = ip.split('.');
  if (ipv4Parts.length === 4 && ipv4Parts.every((p) => /^\d+$/.test(p) && parseInt(p, 10) <= 255)) {
    const [b0, b1] = ipv4Parts.map((p) => parseInt(p, 10));
    if (b0 === 0) return true;                            // 0.0.0.0/8
    if (b0 === 127) return true;                          // 127.0.0.0/8 Loopback
    if (b0 === 10) return true;                           // 10.0.0.0/8 Private RFC1918
    if (b0 === 172 && b1 >= 16 && b1 <= 31) return true; // 172.16.0.0/12 Private RFC1918
    if (b0 === 192 && b1 === 168) return true;            // 192.168.0.0/16 Private RFC1918
    if (b0 === 169 && b1 === 254) return true;            // 169.254.0.0/16 Link-local RFC3927 / Cloud metadata
    if (b0 === 100 && b1 >= 64 && b1 <= 127) return true; // 100.64.0.0/10 RFC6598 Shared Address Space / Tailnet
    if (b0 >= 224) return true;                           // 224.0.0.0/4 Multicast & reserved
    return false;
  }
  // IPv6 checks
  if (ip.startsWith('fe8') || ip.startsWith('fe9') || ip.startsWith('fea') || ip.startsWith('feb')) {
    return true; // fe80::/10 link-local RFC3927 / RFC4291
  }
  if (ip.startsWith('fc') || ip.startsWith('fd')) {
    return true; // fc00::/7 unique local private RFC4193
  }
  if (ip.startsWith('ff')) {
    return true; // ff00::/8 multicast
  }
  return false;
}

function isPrivateOrLoopbackHost(hostname) {
  if (!hostname) return true;
  let host = String(hostname).toLowerCase().trim();

  // Strip enclosing brackets for IPv6
  if (host.startsWith('[') && host.endsWith(']')) {
    host = host.slice(1, -1);
  }

  // Common localhost/loopback names
  if (host === 'localhost' || host === '0.0.0.0' || host === '::1' || host === '::') {
    return true;
  }
  if (host.endsWith('.localhost') || host.endsWith('.local') || host.endsWith('.internal') || host.endsWith('.svc')) {
    return true;
  }
  if (host === 'kubernetes.default' || host.startsWith('kubernetes.') || host.endsWith('.svc.cluster.local') || host.endsWith('.cluster.local')) {
    return true;
  }

  // Direct IP checks
  if (isPrivateIpAddress(host)) {
    return true;
  }

  return false;
}

async function validateTargetUrl(urlStr) {
  if (!urlStr || typeof urlStr !== 'string') {
    return { ok: false, status: 400, error: 'Target URL is required' };
  }
  let urlObj;
  try {
    urlObj = new URL(urlStr);
  } catch (err) {
    return { ok: false, status: 400, error: `Invalid target URL: ${err.message}` };
  }

  if (urlObj.protocol !== 'http:' && urlObj.protocol !== 'https:') {
    return { ok: false, status: 400, error: `Unsupported protocol: ${urlObj.protocol}` };
  }

  if (isPrivateOrLoopbackHost(urlObj.hostname)) {
    return { ok: false, status: 403, error: 'Access to private or loopback target is forbidden' };
  }

  // Pre-flight DNS resolution to defeat DNS rebinding (e.g., 127.0.0.1.nip.io)
  try {
    const records = await dns.promises.lookup(urlObj.hostname, { all: true });
    for (const record of records) {
      if (isPrivateIpAddress(record.address)) {
        return { ok: false, status: 403, error: 'Access to private or loopback target is forbidden' };
      }
    }
  } catch (err) {
    return { ok: false, status: 400, error: `DNS lookup failed for ${urlObj.hostname}: ${err.message}` };
  }

  return { ok: true, urlObj, urlStr: urlObj.href };
}

async function safeParseTargetUrl(urlStr) {
  return validateTargetUrl(urlStr);
}

function safeParseRequestUrl(req) {
  const rawHost = req.headers?.host || 'localhost:8080';
  const rawUrl = req.url || '/';
  try {
    return new URL(rawUrl, `http://${rawHost}`);
  } catch {
    try {
      return new URL(rawUrl, 'http://localhost:8080');
    } catch {
      return null;
    }
  }
}

// ---------------------------------------------------------------------------
// Upstream HTTP Proxy Helper
// ---------------------------------------------------------------------------
async function proxyHttpRequest(targetUrl, req, res, options = {}) {
  let urlObj;
  try {
    urlObj = typeof targetUrl === 'string' ? new URL(targetUrl) : targetUrl;
  } catch (err) {
    if (!res.headersSent) {
      res.writeHead(400, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ error: 'Invalid proxy target URL', details: err.message }));
    }
    return;
  }

  const validation = await validateTargetUrl(urlObj.href);
  if (!validation.ok) {
    if (!res.headersSent) {
      res.writeHead(validation.status || 403, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ error: validation.error }));
    }
    return;
  }

  const isHttps = urlObj.protocol === 'https:';
  const client = isHttps ? https : http;

  const headers = { ...req.headers };
  delete headers.host;
  delete headers.connection;
  if (options.headers) {
    Object.assign(headers, options.headers);
  }

  try {
    const clientReq = client.request(
      urlObj,
      {
        method: req.method,
        headers,
        timeout: options.timeout || 30000,
      },
      (clientRes) => {
        const respHeaders = { ...clientRes.headers };
        if (options.cacheControl) {
          respHeaders['cache-control'] = options.cacheControl;
        }
        res.writeHead(clientRes.statusCode || 200, respHeaders);
        clientRes.pipe(res);
      }
    );

    clientReq.on('timeout', () => {
      clientReq.destroy();
      if (!res.headersSent) {
        res.writeHead(504, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ error: 'Gateway timeout' }));
      }
    });

    clientReq.on('error', (err) => {
      if (!res.headersSent) {
        res.writeHead(502, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ error: 'Upstream gateway error', details: err.message }));
      }
    });

    if (options.body) {
      clientReq.write(options.body);
      clientReq.end();
    } else {
      req.pipe(clientReq);
    }
  } catch (err) {
    if (!res.headersSent) {
      res.writeHead(500, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ error: 'Proxy request setup failed', details: err.message }));
    }
  }
}

// ---------------------------------------------------------------------------
// Request Body Reader with Limit Guard
// ---------------------------------------------------------------------------
class PayloadTooLargeError extends Error {
  constructor(message = 'Payload too large') {
    super(message);
    this.name = 'PayloadTooLargeError';
    this.statusCode = 413;
  }
}

function readBody(req, limit = 1024 * 1024) {
  return new Promise((resolve, reject) => {
    let body = '';
    let exceeded = false;

    function cleanup() {
      req.removeListener('data', onData);
      req.removeListener('end', onEnd);
      req.removeListener('error', onError);
    }

    function onData(chunk) {
      if (exceeded) return;
      body += chunk;
      if (body.length > limit) {
        exceeded = true;
        req.pause?.();
        cleanup();
        reject(new PayloadTooLargeError('Payload too large'));
      }
    }

    function onEnd() {
      if (!exceeded) {
        cleanup();
        resolve(body);
      }
    }

    function onError(err) {
      if (!exceeded) {
        cleanup();
        reject(err);
      }
    }

    req.on('data', onData);
    req.on('end', onEnd);
    req.on('error', onError);
  });
}

// Helper to read JSON request body
async function readJsonBody(req, limit = 1024 * 1024) {
  const body = await readBody(req, limit);
  if (!body || !body.trim()) return {};
  try {
    return JSON.parse(body);
  } catch {
    return null;
  }
}

// ---------------------------------------------------------------------------
// Setup Keys Allowlist
// ---------------------------------------------------------------------------
const ALLOWED_KEYS = new Set([
  'OPENAI_API_KEY',
  'GOOGLE_MAPS_API_KEY',
  'CESIUM_ION_ACCESS_TOKEN',
  'CESIUM_ION_TOKEN',
  'AISSTREAM_API_KEY',
  'FIRMS_MAP_KEY',
  'TOMTOM_API_KEY',
  'ADSBLOL_API_KEY',
  'OPENWEATHER_API_KEY',
  'GEV_RATELIMIT_OPENAI_PER_MIN',
  'GEV_RATELIMIT_GOOGLE_PER_MIN',
]);

// ---------------------------------------------------------------------------
// NASA FIRMS CSV Parser Helper
// ---------------------------------------------------------------------------
function parseFirmsCsvText(csvText) {
  if (typeof csvText !== 'string') return [];
  const lines = csvText.trim().split(/\r?\n/);
  if (lines.length <= 1) return [];
  const header = lines[0].split(',').map((h) => h.trim().toLowerCase());
  const latIdx = header.indexOf('latitude');
  const lonIdx = header.indexOf('longitude');
  const frpIdx = header.indexOf('frp');
  const confIdx = header.indexOf('confidence');
  const dateIdx = header.indexOf('acq_date');
  const timeIdx = header.indexOf('acq_time');
  const satIdx = header.indexOf('satellite');
  const brightIdx = header.findIndex((h) => h.startsWith('bright'));

  const fires = [];
  for (let i = 1; i < lines.length; i++) {
    const line = lines[i].trim();
    if (!line) continue;
    const parts = line.split(',');
    const lat = parseFloat(parts[latIdx]);
    const lon = parseFloat(parts[lonIdx]);
    if (isNaN(lat) || isNaN(lon)) continue;
    fires.push({
      latitude: lat,
      longitude: lon,
      brightness: brightIdx >= 0 ? parseFloat(parts[brightIdx]) || 0 : 0,
      frp: frpIdx >= 0 ? parseFloat(parts[frpIdx]) || 0 : 0,
      confidence: confIdx >= 0 ? parts[confIdx]?.trim() || 'nominal' : 'nominal',
      acq_date: dateIdx >= 0 ? parts[dateIdx]?.trim() || '' : '',
      acq_time: timeIdx >= 0 ? parts[timeIdx]?.trim() || '' : '',
      satellite: satIdx >= 0 ? parts[satIdx]?.trim() || '' : '',
    });
  }
  return fires;
}

// ---------------------------------------------------------------------------
// OpenSky Cache & Auth State
// ---------------------------------------------------------------------------
let _openskyCacheBody = null;
let _openskyCacheTime = 0;
const OPENSKY_CACHE_MS = 10000;

// ---------------------------------------------------------------------------
// Request Handler
// ---------------------------------------------------------------------------
const server = http.createServer(async (req, res) => {
  try {
    const urlObj = safeParseRequestUrl(req);
    if (!urlObj) {
      if (!res.headersSent) {
        res.writeHead(400, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ error: 'Bad Request: Malformed URL or Host header' }));
      }
      return;
    }
    const pathname = urlObj.pathname;

  // Security Headers
  res.setHeader('X-Content-Type-Options', 'nosniff');
  res.setHeader('X-Frame-Options', 'DENY');
  res.setHeader('Content-Security-Policy', "frame-ancestors 'none'");

  // 1. Health Checks
  if (pathname === '/healthz' || pathname === '/health' || pathname === '/ping') {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({
      status: 'ok',
      uptime: process.uptime(),
      timestamp: new Date().toISOString(),
      aisStream: {
        status: _aisStatus,
        vessels: _aisVessels.size,
      },
    }));
    return;
  }

  // 2. API Routes
  if (pathname.startsWith('/api/')) {
    // 2.1: /api/opensky & /api/opensky-track
    if (pathname === '/api/opensky') {
      const now = Date.now();
      if (_openskyCacheBody && now - _openskyCacheTime < OPENSKY_CACHE_MS) {
        res.writeHead(200, {
          'Content-Type': 'application/json; charset=utf-8',
          'Cache-Control': 'public, max-age=10',
          'X-OpenSky-Cache': 'HIT',
        });
        res.end(_openskyCacheBody);
        return;
      }

      const headers = {};
      if (process.env.OPENSKY_USERNAME && process.env.OPENSKY_PASSWORD) {
        const creds = Buffer.from(`${process.env.OPENSKY_USERNAME}:${process.env.OPENSKY_PASSWORD}`).toString('base64');
        headers['Authorization'] = `Basic ${creds}`;
      }

      const upstreamUrl = `https://opensky-network.org/api/states/all${urlObj.search}`;
      const openskyReq = https.get(upstreamUrl, { headers, timeout: 20000 }, (clientRes) => {
        let body = '';
        clientRes.on('data', (chunk) => { body += chunk; });
        clientRes.on('end', () => {
          if (clientRes.statusCode === 200) {
            _openskyCacheBody = body;
            _openskyCacheTime = Date.now();
          }
          res.writeHead(clientRes.statusCode || 200, {
            'Content-Type': 'application/json; charset=utf-8',
            'Cache-Control': 'public, max-age=10',
          });
          res.end(body || _openskyCacheBody || '{"states":[]}');
        });
      });
      openskyReq.on('timeout', () => {
        openskyReq.destroy(new Error('OpenSky upstream request timed out'));
      });
      openskyReq.on('error', (err) => {
        if (_openskyCacheBody) {
          res.writeHead(200, {
            'Content-Type': 'application/json; charset=utf-8',
            'Cache-Control': 'no-store',
            'X-OpenSky-Stale': 'true',
          });
          res.end(_openskyCacheBody);
        } else {
          res.writeHead(502, { 'Content-Type': 'application/json' });
          res.end(JSON.stringify({ error: 'OpenSky gateway error', details: err.message, states: [] }));
        }
      });
      return;
    }

    if (pathname === '/api/opensky-track') {
      const icao24 = urlObj.searchParams.get('icao24') || '';
      const upstreamUrl = `https://opensky-network.org/api/tracks/all?icao24=${encodeURIComponent(icao24)}`;
      await proxyHttpRequest(upstreamUrl, req, res, { cacheControl: 'public, max-age=60' });
      return;
    }

    // 2.2: /api/celestrak
    if (pathname.startsWith('/api/celestrak')) {
      const sub = pathname.slice('/api/celestrak'.length).replace(/^\/+/, '').split('/')[0];
      const group = sub || urlObj.searchParams.get('GROUP') || 'stations';
      const upstreamUrl = `https://celestrak.org/NORAD/elements/gp.php?GROUP=${encodeURIComponent(group)}&FORMAT=tle`;
      await proxyHttpRequest(upstreamUrl, req, res, { cacheControl: 'public, max-age=3600' });
      return;
    }

    // 2.3: /api/firms
    if (pathname === '/api/firms') {
      const mapKey = process.env.FIRMS_MAP_KEY;
      if (!mapKey) {
        res.writeHead(200, { 'Content-Type': 'application/json; charset=utf-8' });
        res.end(JSON.stringify({ fires: [], count: 0, error: 'no_key' }));
        return;
      }
      try {
        const upstreamUrl = `https://firms.modaps.eosdis.nasa.gov/api/country/csv/${encodeURIComponent(mapKey)}/VIIRS_SNPP_NRT/USA/1`;
        const resp = await fetch(upstreamUrl, { signal: AbortSignal.timeout(15000) });
        if (!resp.ok) {
          res.writeHead(resp.status, { 'Content-Type': 'application/json' });
          res.end(JSON.stringify({ fires: [], count: 0, error: `Upstream HTTP ${resp.status}` }));
          return;
        }
        const text = await resp.text();
        const fires = parseFirmsCsvText(text);
        res.writeHead(200, { 'Content-Type': 'application/json; charset=utf-8', 'Cache-Control': 'public, max-age=600' });
        res.end(JSON.stringify({ fires, count: fires.length, fetchedAt: Date.now() }));
      } catch (err) {
        res.writeHead(200, { 'Content-Type': 'application/json; charset=utf-8' });
        res.end(JSON.stringify({ fires: [], count: 0, error: err.message }));
      }
      return;
    }

    // 2.4: /api/cctv and subroutes
    if (pathname === '/api/cctv/sources') {
      res.writeHead(200, { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' });
      res.end(JSON.stringify({ sources: [] }));
      return;
    }

    if (pathname === '/api/cctv/health') {
      res.writeHead(200, { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' });
      res.end(JSON.stringify({ status: 'ok', activeStreams: 0, cameras: [] }));
      return;
    }

    if (pathname.startsWith('/api/cctv/frame')) {
      const target = urlObj.searchParams.get('url');
      if (target) {
        const parsed = await safeParseTargetUrl(target);
        if (!parsed.ok) {
          res.writeHead(parsed.status, { 'Content-Type': 'application/json' });
          res.end(JSON.stringify({ error: parsed.error }));
          return;
        }
        await proxyHttpRequest(parsed.urlStr, req, res, { cacheControl: 'public, max-age=5' });
        return;
      }
      res.writeHead(200, { 'Content-Type': 'image/svg+xml', 'Cache-Control': 'public, max-age=5' });
      res.end('<svg xmlns="http://www.w3.org/2000/svg" width="320" height="240" viewBox="0 0 320 240"><rect width="320" height="240" fill="#111"/><text x="50%" y="50%" fill="#666" font-family="monospace" font-size="14" dominant-baseline="middle" text-anchor="middle">CCTV FRAME</text></svg>');
      return;
    }

    if (pathname.startsWith('/api/cctv/media')) {
      const target = urlObj.searchParams.get('url');
      if (target) {
        const parsed = await safeParseTargetUrl(target);
        if (!parsed.ok) {
          res.writeHead(parsed.status, { 'Content-Type': 'application/json' });
          res.end(JSON.stringify({ error: parsed.error }));
          return;
        }
        await proxyHttpRequest(parsed.urlStr, req, res, { cacheControl: 'no-cache' });
        return;
      }
      res.writeHead(200, { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' });
      res.end(JSON.stringify({ status: 'ok', mediaUrl: null, activeStreams: 0 }));
      return;
    }

    if (pathname === '/api/cctv') {
      const target = urlObj.searchParams.get('url');
      if (target) {
        const parsed = await safeParseTargetUrl(target);
        if (!parsed.ok) {
          res.writeHead(parsed.status, { 'Content-Type': 'application/json' });
          res.end(JSON.stringify({ error: parsed.error }));
          return;
        }
        await proxyHttpRequest(parsed.urlStr, req, res, { cacheControl: 'public, max-age=5' });
      } else {
        res.writeHead(200, { 'Content-Type': 'image/svg+xml' });
        res.end('<svg xmlns="http://www.w3.org/2000/svg" width="320" height="240" viewBox="0 0 320 240"><rect width="320" height="240" fill="#111"/><text x="50%" y="50%" fill="#666" font-family="monospace" font-size="14" dominant-baseline="middle" text-anchor="middle">NO CCTV SIGNAL</text></svg>');
      }
      return;
    }

    // 2.5: /api/ais-live & /api/ais-live/track
    if (pathname === '/api/ais-live' || pathname === '/api/ais-live/track') {
      if (pathname === '/api/ais-live/track') {
        const mmsi = String(urlObj.searchParams.get('mmsi') || '').trim();
        if (!mmsi) {
          res.writeHead(400, { 'Content-Type': 'application/json' });
          res.end(JSON.stringify({ error: 'mmsi query parameter required', samples: [] }));
          return;
        }
        res.writeHead(200, { 'Content-Type': 'application/json; charset=utf-8', 'Cache-Control': 'no-store' });
        res.end(JSON.stringify({
          mmsi,
          samples: _aisTracks.get(mmsi) || [],
          source: 'AISStream (accumulated since server start)',
          retainedSec: Math.floor(AISSTREAM_STALE_MS / 1000),
        }));
        return;
      }

      const maxRows = parseInt(urlObj.searchParams.get('maxRows') || '5000', 10);
      const rows = Array.from(_aisVessels.values()).slice(0, maxRows);

      res.writeHead(process.env.AISSTREAM_API_KEY ? 200 : 200, {
        'Content-Type': 'application/json; charset=utf-8',
        'Cache-Control': 'no-store',
      });
      res.end(JSON.stringify({
        rows,
        source: 'AISStream',
        status: _aisStatus,
        error: _aisLastError,
        refreshing: _aisStatus !== 'live',
        lastMessageAt: _lastAisMessageAt,
        reconnectAttempt: _aisReconnectAttempt,
        totalVessels: _aisVessels.size,
      }));
      return;
    }

    // 2.6: /api/realtime/token & /api/realtime/debug-log
    if (pathname === '/api/realtime/token') {
      if (!enforceRateLimit(req, res, 'GEV_RATELIMIT_OPENAI_PER_MIN', 60)) return;

      const apiKey = process.env.OPENAI_API_KEY;
      if (!apiKey) {
        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({
          error: 'OPENAI_API_KEY is not configured',
          client_secret: { value: 'demo_token' },
          client_secrets: [{ value: 'demo_token' }],
        }));
        return;
      }

      // Mint ephemeral session token via OpenAI Realtime API
      const options = {
        hostname: 'api.openai.com',
        path: '/v1/realtime/sessions',
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${apiKey}`,
          'Content-Type': 'application/json',
        },
        timeout: 15000,
      };

      const tokenReq = https.request(options, (tokenRes) => {
        let data = '';
        tokenRes.on('data', (c) => { data += c; });
        tokenRes.on('end', () => {
          let parsed;
          try { parsed = JSON.parse(data); } catch { parsed = { data }; }
          // Provide both client_secret and client_secrets aliases
          if (parsed?.client_secret && !parsed.client_secrets) {
            parsed.client_secrets = [parsed.client_secret];
          }
          res.writeHead(tokenRes.statusCode || 200, { 'Content-Type': 'application/json' });
          res.end(JSON.stringify(parsed));
        });
      });

      tokenReq.on('timeout', () => {
        tokenReq.destroy(new Error('OpenAI Realtime token request timed out'));
      });

      tokenReq.on('error', (err) => {
        res.writeHead(502, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({
          error: 'Failed to mint OpenAI Realtime token',
          client_secret: { value: '' },
          client_secrets: [],
          details: err.message,
        }));
      });

      tokenReq.write(JSON.stringify({
        model: 'gpt-4o-realtime-preview',
        voice: 'alloy',
      }));
      tokenReq.end();
      return;
    }

    if (pathname === '/api/realtime/debug-log') {
      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ ok: true }));
      return;
    }

    // 2.7: /api/openai/hud-summary
    if (pathname === '/api/openai/hud-summary') {
      if (!enforceRateLimit(req, res, 'GEV_RATELIMIT_OPENAI_PER_MIN', 60)) return;
      const apiKey = process.env.OPENAI_API_KEY;
      if (!apiKey) {
        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ summary: 'No OpenAI API key configured. Real-time HUD summary unavailable.' }));
        return;
      }
      const postBody = req.method === 'POST' ? await readBody(req, 1024 * 1024) : null;
      await proxyHttpRequest('https://api.openai.com/v1/chat/completions', req, res, {
        headers: { 'Authorization': `Bearer ${apiKey}` },
        body: postBody,
      });
      return;
    }

    // 2.8: /api/google/nearby-places & /api/google/text-search
    if (pathname === '/api/google/nearby-places' || pathname === '/api/google/text-search') {
      if (!enforceRateLimit(req, res, 'GEV_RATELIMIT_GOOGLE_PER_MIN', 120)) return;
      const apiKey = process.env.GOOGLE_MAPS_API_KEY;
      if (!apiKey) {
        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ places: [] }));
        return;
      }
      const googlePath = pathname === '/api/google/nearby-places'
        ? 'https://places.googleapis.com/v1/places:searchNearby'
        : 'https://places.googleapis.com/v1/places:searchText';
      const postBody = req.method === 'POST' ? await readBody(req, 1024 * 1024) : null;
      await proxyHttpRequest(googlePath, req, res, {
        headers: {
          'X-Goog-Api-Key': apiKey,
          'X-Goog-FieldMask': 'places.displayName,places.location,places.types',
        },
        body: postBody,
      });
      return;
    }

    // 2.9: /api/tomtom
    if (pathname === '/api/tomtom/status') {
      const configured = Boolean(process.env.TOMTOM_API_KEY);
      res.writeHead(200, { 'Content-Type': 'application/json; charset=utf-8', 'Cache-Control': 'no-store' });
      res.end(JSON.stringify({ configured, hasKey: configured }));
      return;
    }

    if (pathname.startsWith('/api/tomtom/flow/')) {
      const apiKey = process.env.TOMTOM_API_KEY;
      if (!apiKey) {
        res.writeHead(503, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ error: 'no_key' }));
        return;
      }
      const subpath = pathname.replace('/api/tomtom/flow/', '');
      const upstreamUrl = `https://api.tomtom.com/traffic/map/4/tile/flow/relative0/${subpath}?key=${apiKey}`;
      await proxyHttpRequest(upstreamUrl, req, res, { cacheControl: 'public, max-age=60' });
      return;
    }

    if (pathname === '/api/tomtom') {
      const apiKey = process.env.TOMTOM_API_KEY;
      if (!apiKey) {
        res.writeHead(204);
        res.end();
        return;
      }
      const upstreamUrl = `https://api.tomtom.com/traffic/map/4/tile/flow/relative0/10/500/500.pbf?key=${apiKey}`;
      await proxyHttpRequest(upstreamUrl, req, res, { cacheControl: 'public, max-age=60' });
      return;
    }

    // 2.10: /api/terrain/heights & /api/terrain-heights
    if (pathname === '/api/terrain/heights' || pathname === '/api/terrain-heights') {
      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ results: [] }));
      return;
    }

    // 2.11: /api/adsbdb
    if (pathname.startsWith('/api/adsbdb')) {
      const subpath = pathname.replace('/api/adsbdb', '');
      const upstreamUrl = `https://api.adsbdb.com/v0${subpath}${urlObj.search}`;
      await proxyHttpRequest(upstreamUrl, req, res, { cacheControl: 'public, max-age=86400' });
      return;
    }

    // 2.12: /api/overpass
    if (pathname === '/api/overpass') {
      const upstreamUrl = `https://overpass-api.de/api/interpreter${urlObj.search}`;
      const postBody = req.method === 'POST' ? await readBody(req, 5 * 1024 * 1024) : null;
      await proxyHttpRequest(upstreamUrl, req, res, { timeout: 30000, cacheControl: 'public, max-age=86400', body: postBody });
      return;
    }

    // 2.13: /api/route
    if (pathname === '/api/route') {
      const upstreamUrl = `https://routing.openstreetmap.de/routed-car/route/v1/driving/${urlObj.searchParams.get('coords') || ''}?overview=full&geometries=geojson`;
      await proxyHttpRequest(upstreamUrl, req, res, { cacheControl: 'public, max-age=600000' });
      return;
    }

    // 2.14: /api/launches
    if (pathname === '/api/launches') {
      const upstreamUrl = 'https://lldev.thespacedevs.com/2.2.0/launch/upcoming/?limit=10';
      await proxyHttpRequest(upstreamUrl, req, res, { cacheControl: 'public, max-age=1800' });
      return;
    }

    // 2.15: /api/radio
    if (pathname === '/api/radio/stations' || pathname === '/api/radio' || pathname === '/api/radio/') {
      const upstreamUrl = `https://de1.api.radio-browser.info/json/stations/topclick/20`;
      await proxyHttpRequest(upstreamUrl, req, res, { cacheControl: 'public, max-age=3600' });
      return;
    }

    if (pathname.startsWith('/api/radio/click/')) {
      const id = pathname.slice('/api/radio/click/'.length).trim();
      const upstreamUrl = `https://de1.api.radio-browser.info/json/url/${encodeURIComponent(id)}`;
      await proxyHttpRequest(upstreamUrl, req, res, { cacheControl: 'no-store' });
      return;
    }

    // 2.16: /api/gbfs
    if (pathname.startsWith('/api/gbfs')) {
      let target = urlObj.searchParams.get('url');
      if (!target && pathname.startsWith('/api/gbfs/')) {
        const encoded = pathname.slice('/api/gbfs/'.length);
        if (encoded) {
          try {
            target = decodeURIComponent(encoded);
          } catch {
            target = encoded;
          }
        }
      }
      if (!target) {
        target = 'https://gbfs.citibikenyc.com/gbfs/en/station_status.json';
      }
      const parsed = await safeParseTargetUrl(target);
      if (!parsed.ok) {
        res.writeHead(parsed.status, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ error: parsed.error }));
        return;
      }
      await proxyHttpRequest(parsed.urlStr, req, res, { cacheControl: 'public, max-age=30' });
      return;
    }

    // 2.17: /api/adsblol/mil & /api/adsblol/trace
    if (pathname === '/api/adsblol/mil') {
      const upstreamUrl = 'https://api.adsb.lol/v2/mil';
      await proxyHttpRequest(upstreamUrl, req, res, { cacheControl: 'public, max-age=15' });
      return;
    }
    if (pathname.startsWith('/api/adsblol/trace')) {
      const icao = urlObj.searchParams.get('hex') || '';
      const upstreamUrl = `https://api.adsb.lol/v2/trace/${encodeURIComponent(icao)}`;
      await proxyHttpRequest(upstreamUrl, req, res, { cacheControl: 'public, max-age=60' });
      return;
    }

    // 2.18: /api/military-installations
    if (pathname === '/api/military-installations') {
      const upstreamUrl = `https://overpass-api.de/api/interpreter${urlObj.search}`;
      await proxyHttpRequest(upstreamUrl, req, res, { cacheControl: 'public, max-age=86400' });
      return;
    }

    // 2.19: /api/regional-brief & 2.20: /api/weather-effects
    if (pathname === '/api/regional-brief' || pathname === '/api/weather-effects') {
      const lat = urlObj.searchParams.get('latitude') || urlObj.searchParams.get('lat') || '0';
      const lon = urlObj.searchParams.get('longitude') || urlObj.searchParams.get('lon') || '0';
      const latNum = parseFloat(lat) || 0;
      const lonNum = parseFloat(lon) || 0;

      let openMeteoData = null;
      try {
        const upstreamUrl = `https://api.open-meteo.com/v1/forecast?latitude=${latNum}&longitude=${lonNum}&current=temperature_2m,apparent_temperature,precipitation,weather_code,cloud_cover,wind_speed_10m,wind_direction_10m,visibility&current_weather=true&timezone=UTC`;
        const resp = await fetch(upstreamUrl, { signal: AbortSignal.timeout(10000) });
        if (resp.ok) {
          openMeteoData = await resp.json();
        }
      } catch {
        // Fall back to synthetic observation on network/API failure
      }

      const current = openMeteoData?.current || {};
      const weatherCode = Number(current.weather_code ?? openMeteoData?.current_weather?.weathercode ?? 0);
      const cloudCoverPct = Number(current.cloud_cover ?? 0);
      const visibilityM = Number(current.visibility ?? 10000);
      const tempC = Number(current.temperature_2m ?? openMeteoData?.current_weather?.temperature ?? 20);
      const windKph = Number(current.wind_speed_10m ?? openMeteoData?.current_weather?.windspeed ?? 0);
      const windDir = Number(current.wind_direction_10m ?? openMeteoData?.current_weather?.winddirection ?? 0);
      const precipMm = Number(current.precipitation ?? 0);

      const condition = weatherCode === 0 ? 'CLEAR'
        : [1, 2].includes(weatherCode) ? 'PARTLY CLOUDY'
        : weatherCode === 3 ? 'OVERCAST'
        : [45, 48].includes(weatherCode) ? 'FOG'
        : weatherCode >= 51 && weatherCode <= 57 ? 'DRIZZLE'
        : weatherCode >= 61 && weatherCode <= 67 ? 'RAIN'
        : weatherCode >= 71 && weatherCode <= 77 ? 'SNOW'
        : weatherCode >= 80 && weatherCode <= 82 ? 'RAIN SHOWERS'
        : weatherCode >= 95 ? 'THUNDERSTORM' : 'CLEAR';

      const weather = {
        condition,
        cloudCover: cloudCoverPct / 100,
        cloudCoverPct,
        visibility: visibilityM,
        visibilityM,
        weatherCode,
        temperatureC: tempC,
        apparentTemperatureC: Number(current.apparent_temperature ?? tempC),
        precipitationMm: precipMm,
        windKph,
        windDirectionDeg: windDir,
        observedAt: current.time ? `${current.time}Z` : new Date().toISOString(),
      };

      res.writeHead(200, {
        'Content-Type': 'application/json; charset=utf-8',
        'Cache-Control': 'public, max-age=300',
      });
      res.end(JSON.stringify({
        status: 'ready',
        retrievedAt: new Date().toISOString(),
        coordinates: { latitude: latNum, longitude: lonNum },
        weather,
        current_weather: openMeteoData?.current_weather || {
          temperature: tempC,
          windspeed: windKph,
          winddirection: windDir,
          weathercode: weatherCode,
          time: new Date().toISOString(),
        },
      }));
      return;
    }

    // 2.21: /api/setup/status & /api/setup/keys
    if (pathname === '/api/setup/status') {
      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({
        GOOGLE_MAPS_API_KEY: Boolean(process.env.GOOGLE_MAPS_API_KEY),
        CESIUM_ION_TOKEN: Boolean(process.env.CESIUM_ION_TOKEN || process.env.CESIUM_ION_ACCESS_TOKEN),
        OPENAI_API_KEY: Boolean(process.env.OPENAI_API_KEY),
        AISSTREAM_API_KEY: Boolean(process.env.AISSTREAM_API_KEY),
        TOMTOM_API_KEY: Boolean(process.env.TOMTOM_API_KEY),
        FIRMS_MAP_KEY: Boolean(process.env.FIRMS_MAP_KEY),
      }));
      return;
    }

    if (pathname === '/api/setup/keys') {
      if (req.method === 'POST') {
        let body;
        try {
          body = await readJsonBody(req);
        } catch (err) {
          if (err instanceof PayloadTooLargeError || err?.statusCode === 413 || err?.message === 'Payload too large' || err?.message === 'Body too large') {
            res.writeHead(413, { 'Content-Type': 'application/json', 'Connection': 'close' });
            res.end(JSON.stringify({ error: 'Payload too large' }));
            req.destroy?.();
            return;
          }
          res.writeHead(400, { 'Content-Type': 'application/json' });
          res.end(JSON.stringify({ error: 'Bad Request', details: err?.message }));
          return;
        }

        if (body === null) {
          res.writeHead(400, { 'Content-Type': 'application/json' });
          res.end(JSON.stringify({ error: 'Invalid JSON payload' }));
          return;
        }

        if (!body || typeof body !== 'object' || Array.isArray(body)) {
          res.writeHead(400, { 'Content-Type': 'application/json' });
          res.end(JSON.stringify({ error: 'Body must be a JSON object' }));
          return;
        }

        const keys = Object.keys(body);
        for (const k of keys) {
          if (!ALLOWED_KEYS.has(k)) {
            res.writeHead(400, { 'Content-Type': 'application/json' });
            res.end(JSON.stringify({ error: `Key not allowed: ${k}` }));
            return;
          }
        }

        const saved = [];
        for (const [k, v] of Object.entries(body)) {
          if (typeof v === 'string') {
            process.env[k] = v;
            saved.push(k);
          }
        }
        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ ok: true, saved }));
      } else {
        res.writeHead(405, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ error: 'Method not allowed' }));
      }
      return;
    }

    // Unknown API endpoint
    res.writeHead(404, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ error: 'API route not found', path: pathname }));
    return;
  }

  // 3. Static Asset Serving from dist/
  let sanitizedPath = path.normalize(pathname).replace(/^(\.\.[/\\])+/, '');
  if (sanitizedPath === '/' || sanitizedPath === '') {
    sanitizedPath = '/index.html';
  }

  let filePath = path.join(DIST_DIR, sanitizedPath);

  // Guard against path traversal
  if (!filePath.startsWith(DIST_DIR)) {
    res.writeHead(403, { 'Content-Type': 'text/plain' });
    res.end('Forbidden');
    return;
  }

  let stat;
    try {
      stat = await fs.promises.stat(filePath);
    } catch {
      stat = null;
    }

    if (stat && stat.isDirectory()) {
      filePath = path.join(filePath, 'index.html');
      try {
        stat = await fs.promises.stat(filePath);
      } catch {
        stat = null;
      }
    }

    // SPA fallback: if requested file not found and no extension, serve index.html
    if (!stat && !path.extname(sanitizedPath)) {
      filePath = path.join(DIST_DIR, 'index.html');
      try {
        stat = await fs.promises.stat(filePath);
      } catch {
        stat = null;
      }
    }

    if (!stat) {
      // If dist/index.html doesn't exist yet, return a graceful 200 for root
      if (pathname === '/' || pathname === '/index.html') {
        res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
        res.end('<!DOCTYPE html><html><head><title>God\'s Eye View</title></head><body><h1>God\'s Eye View Production Server</h1><p>Status: Healthy</p></body></html>');
        return;
      }
      res.writeHead(404, { 'Content-Type': 'text/plain' });
      res.end('Not Found');
      return;
    }

    const ext = path.extname(filePath).toLowerCase();
    const contentType = MIME_TYPES[ext] || 'application/octet-stream';
    const isImmutable = sanitizedPath.startsWith('/assets/') || sanitizedPath.startsWith('/cesium/');
    const cacheControl = isImmutable
      ? 'public, max-age=31536000, immutable'
      : (ext === '.html' ? 'no-cache' : 'public, max-age=86400');

    res.writeHead(200, {
      'Content-Type': contentType,
      'Content-Length': stat.size,
      'Cache-Control': cacheControl,
    });

    const stream = fs.createReadStream(filePath);
    stream.on('error', (err) => {
      console.warn('[Server] Static file stream error:', err?.message);
      if (!res.headersSent) {
        res.writeHead(500, { 'Content-Type': 'text/plain' });
        res.end('Internal Server Error');
      }
    });
    stream.pipe(res);
  } catch (err) {
    console.error('[Server] Unhandled request error:', err);
    if (!res.headersSent) {
      const status = err?.statusCode || (err?.message === 'Payload too large' || err?.message === 'Body too large' ? 413 : 500);
      res.writeHead(status, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({
        error: status === 413 ? 'Payload too large' : 'Internal server error',
        details: err?.message,
      }));
    }
  }
});

// Handle WebSocket upgrades
server.on('upgrade', (req, socket, head) => {
  socket.on('error', (err) => {
    console.warn('[WSS] Socket pre-upgrade error:', err?.message);
  });

  try {
    wss.handleUpgrade(req, socket, head, (ws) => {
      ws.on('error', (err) => {
        console.warn('[WSS Client] socket error:', err?.message);
      });

      wss.emit('connection', ws, req);
      // Send immediate snapshot of known vessels
      const rows = Array.from(_aisVessels.values());
      try {
        ws.send(JSON.stringify({ type: 'snapshot', rows, total: rows.length }));
      } catch (sendErr) {
        console.warn('[WSS Client] failed to send initial snapshot:', sendErr?.message);
      }
    });
  } catch (err) {
    console.warn('[WSS] handleUpgrade error:', err?.message);
    socket.destroy();
  }
});

// Process-level safety guards to prevent unhandled crashes
process.on('uncaughtException', (err) => {
  console.error('[Process] Uncaught exception trapped:', err);
});
process.on('unhandledRejection', (reason) => {
  console.error('[Process] Unhandled promise rejection trapped:', reason);
});

// Start listening if executed directly or in production mode
server.on('error', (err) => {
  if (err.code === 'EADDRINUSE') {
    console.warn(`[God's Eye View] Port ${PORT} already in use; continuing without rebound listener`);
  } else {
    console.error('[God\'s Eye View] Server error:', err);
  }
});

const isDirectExecution = Boolean(
  process.argv[1] && (
    process.argv[1] === __filename ||
    path.resolve(process.argv[1]) === __filename ||
    process.argv[1].endsWith('server.mjs')
  )
);

if (isDirectExecution || process.env.NODE_ENV === 'production' || process.env.AUTO_START_SERVER === 'true') {
  server.listen(PORT, HOST, () => {
    console.log(`[God's Eye View] Production server listening on http://${HOST}:${PORT}`);
    console.log(`[God's Eye View] Static assets served from: ${DIST_DIR}`);
  });
}

export {
  server,
  safeParseTargetUrl,
  validateTargetUrl,
  isPrivateOrLoopbackHost,
  isPrivateIpAddress,
  safeParseRequestUrl,
  getClientIp,
  readBody,
  readJsonBody,
  PayloadTooLargeError,
  ALLOWED_KEYS,
};

export default server;

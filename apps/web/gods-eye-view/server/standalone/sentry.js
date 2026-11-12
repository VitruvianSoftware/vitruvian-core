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

import crypto from 'node:crypto';
import * as Sentry from '@sentry/node';
import { admitSameSiteKeyless } from '../providers/common/same-site.js';

let initialized = false;

/**
 * Initializes server-side Sentry error tracking if SENTRY_DSN is configured.
 * Gracefully no-ops if SENTRY_DSN is empty.
 * @returns {boolean} Whether Sentry was initialized.
 */
export function initServerSentry() {
  const dsn = (process.env.SENTRY_DSN || '').trim();
  if (!dsn) {
    return false;
  }
  if (initialized) {
    return true;
  }

  const tracesSampleRate = Number(process.env.SENTRY_TRACES_SAMPLE_RATE || 0);

  Sentry.init({
    dsn,
    environment: process.env.NODE_ENV || 'production',
    serverName: process.env.HOSTNAME || 'gods-eye-view-server',
    sampleRate: 1.0,
    tracesSampleRate,
  });

  initialized = true;
  console.log("[God's Eye View] Sentry server error monitoring initialized");
  return true;
}

/**
 * Captures an exception to Sentry if initialized.
 * @param {unknown} err
 * @param {Record<string, unknown>} [context]
 * @returns {string | undefined} Event ID if captured.
 */
export function captureServerException(err, context = {}) {
  if (!initialized) return undefined;
  return Sentry.captureException(err, { extra: context });
}

/**
 * Whether server Sentry is initialized.
 * @returns {boolean}
 */
export function isServerSentryInitialized() {
  return initialized;
}

/**
 * Verifies if the request carries a valid GEV_DIAGNOSTICS_TOKEN.
 * @param {import('node:http').IncomingMessage} req
 * @returns {boolean}
 */
function hasValidDiagnosticsToken(req) {
  const expectedToken = (process.env.GEV_DIAGNOSTICS_TOKEN || '').trim();
  if (!expectedToken) return false;
  const authHeader = req.headers?.authorization || '';
  if (!authHeader.startsWith('Bearer ')) return false;
  const token = authHeader.slice(7);
  const expectedBuf = Buffer.from(expectedToken);
  const actualBuf = Buffer.from(token);
  return expectedBuf.length === actualBuf.length && crypto.timingSafeEqual(expectedBuf, actualBuf);
}

/**
 * Whether diagnostics routes are allowed to be served.
 * @returns {boolean}
 */
function areDiagnosticsAllowed() {
  return process.env.GEV_ENABLE_DIAGNOSTICS === 'true' || process.env.NODE_ENV !== 'production';
}

/**
 * Diagnostics route plugin providing:
 * - `GET /api/diagnostics/sentry-config` to serve runtime client Sentry config
 * - `GET /api/diagnostics/sentry-test` to trigger a test exception for end-to-end verification
 */
export function sentryDiagnosticPlugin() {
  const install = (server) => {
    // 1. Runtime public Sentry configuration for browser clients
    server.middlewares.use('/api/diagnostics/sentry-config', (req, res) => {
      if (req.method !== 'GET') {
        res.writeHead(405, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ error: 'Method Not Allowed' }));
        return;
      }

      if (admitSameSiteKeyless(req, res)) {
        return;
      }

      res.writeHead(200, {
        'Content-Type': 'application/json',
        'Cache-Control': 'no-store',
      });
      res.end(
        JSON.stringify({
          dsn: process.env.SENTRY_PUBLIC_DSN || process.env.VITE_SENTRY_DSN || '',
          environment: process.env.SENTRY_ENVIRONMENT || process.env.NODE_ENV || 'production',
          diagnosticsEnabled: areDiagnosticsAllowed(),
          tracesSampleRate: Number(process.env.SENTRY_TRACES_SAMPLE_RATE || 0),
        }),
      );
    });

    // 2. Sentry diagnostic test route
    server.middlewares.use('/api/diagnostics/sentry-test', (req, res) => {
      if (req.method !== 'GET') {
        res.writeHead(405, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ error: 'Method Not Allowed' }));
        return;
      }

      const tokenAuth = hasValidDiagnosticsToken(req);
      const diagnosticsAllowed = areDiagnosticsAllowed();

      // In production, return 404 unless explicitly enabled or authorized with token
      if (!tokenAuth && !diagnosticsAllowed) {
        res.writeHead(404, { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' });
        res.end(JSON.stringify({ error: 'Not Found' }));
        return;
      }

      // If diagnostics enabled but no bearer token, enforce same-site keyless admission
      if (!tokenAuth && admitSameSiteKeyless(req, res)) {
        return;
      }

      const testError = new Error(
        `[God's Eye View] Sentry server diagnostic test exception (${new Date().toISOString()})`,
      );
      const eventId = captureServerException(testError, {
        source: 'sentry-diagnostic-endpoint',
        url: req.url,
      });

      res.writeHead(200, {
        'Content-Type': 'application/json',
        'Cache-Control': 'no-store',
      });
      res.end(
        JSON.stringify({
          status: 'ok',
          message: 'Sentry server diagnostic test exception triggered',
          sentryInitialized: initialized,
          eventId: eventId || null,
          timestamp: new Date().toISOString(),
        }),
      );
    });
  };

  return {
    name: 'gev-sentry-diagnostics',
    configureServer(server) {
      install(server);
    },
    configurePreviewServer(server) {
      install(server);
    },
  };
}

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

import * as Sentry from '@sentry/vue';

let clientInitialized = false;
let diagnosticsEnabled = false;
const diagnosticsListeners = new Set();

/**
 * Subscribes to diagnostics state changes.
 * @param {(enabled: boolean) => void} fn
 * @returns {() => void} Unsubscribe function.
 */
export function onDiagnosticsChange(fn) {
  diagnosticsListeners.add(fn);
  return () => diagnosticsListeners.delete(fn);
}

function notifyDiagnosticsListeners() {
  const active = diagnosticsEnabled || clientInitialized;
  for (const fn of diagnosticsListeners) {
    try {
      fn(active);
    } catch {}
  }
}

/**
 * Fetches runtime Sentry public configuration from the server.
 * Allows production containers to receive Sentry DSN without needing build-time Vite injection.
 * @returns {Promise<{ dsn: string, environment: string, diagnosticsEnabled: boolean, tracesSampleRate: number } | null>}
 */
export async function fetchRuntimeSentryConfig() {
  if (typeof window === 'undefined' || typeof fetch !== 'function') {
    return null;
  }
  try {
    const res = await fetch('/api/diagnostics/sentry-config', {
      headers: { Accept: 'application/json' },
    });
    if (!res.ok) return null;
    return await res.json();
  } catch {
    return null;
  }
}

/**
 * Initializes client-side Sentry error monitoring sending to public Relay ingest.
 * Checks runtime server config (/api/diagnostics/sentry-config), window.__GEV_SENTRY__,
 * and falls back to build-time VITE_SENTRY_DSN. Gracefully no-ops if no DSN is provided.
 *
 * @param {import('vue').App} [app] Optional Vue application instance for error boundary integration.
 * @param {Record<string, unknown>} [options] Optional override configuration.
 * @returns {Promise<boolean>} Whether Sentry was initialized.
 */
export async function initClientSentry(app, options = {}) {
  if (clientInitialized) {
    if (app) attachVueApp(app);
    return true;
  }

  let dsn = (options.dsn || (typeof window !== 'undefined' && window.__GEV_SENTRY__?.dsn) || import.meta.env?.VITE_SENTRY_DSN || '').trim();
  let environment = options.environment || (typeof window !== 'undefined' && window.__GEV_SENTRY__?.environment) || import.meta.env?.MODE || 'production';
  let tracesSampleRate = options.tracesSampleRate ?? (typeof window !== 'undefined' && window.__GEV_SENTRY__?.tracesSampleRate) ?? 0;
  diagnosticsEnabled = Boolean(options.diagnosticsEnabled ?? (typeof window !== 'undefined' && window.__GEV_SENTRY__?.diagnosticsEnabled) ?? import.meta.env?.DEV);

  // If DSN was not injected at build time, query runtime server configuration
  if (!dsn && typeof window !== 'undefined' && typeof fetch === 'function') {
    const runtimeConfig = await fetchRuntimeSentryConfig();
    if (runtimeConfig) {
      if (runtimeConfig.dsn) dsn = runtimeConfig.dsn.trim();
      if (runtimeConfig.environment) environment = runtimeConfig.environment;
      if (runtimeConfig.tracesSampleRate !== undefined) tracesSampleRate = Number(runtimeConfig.tracesSampleRate || 0);
      if (runtimeConfig.diagnosticsEnabled !== undefined) diagnosticsEnabled = Boolean(runtimeConfig.diagnosticsEnabled);
      notifyDiagnosticsListeners();
    }
  }

  if (!dsn) {
    return false;
  }

  Sentry.init({
    app,
    dsn,
    environment,
    sampleRate: 1.0,
    tracesSampleRate: Number(tracesSampleRate || 0),
  });

  clientInitialized = true;
  notifyDiagnosticsListeners();
  console.log("[God's Eye View] Sentry client error monitoring initialized");
  return true;
}

/**
 * Attaches a Vue application instance to Sentry error tracking.
 * @param {import('vue').App} app
 */
export function attachVueApp(app) {
  if (!app) return;
  const existingHandler = app.config.errorHandler;
  app.config.errorHandler = (error, instance, info) => {
    captureClientException(error, { vueComponent: instance?.$options?.name || 'anonymous', lifecycleHook: info });
    if (typeof existingHandler === 'function') {
      existingHandler(error, instance, info);
    }
  };
}

/**
 * Captures an exception in client-side Sentry if initialized.
 * @param {unknown} err
 * @param {Record<string, unknown>} [context]
 * @returns {string | undefined} Event ID if captured.
 */
export function captureClientException(err, context = {}) {
  if (!clientInitialized) return undefined;
  return Sentry.captureException(err, { extra: context });
}

/**
 * Triggers a test client-side exception to verify Sentry ingest.
 * @returns {string | undefined} Event ID if captured.
 */
export function triggerClientTestException() {
  const testError = new Error(
    `[God's Eye View] Sentry client diagnostic test exception (${new Date().toISOString()})`,
  );
  return captureClientException(testError, {
    source: 'client-diagnostic-test',
    userAgent: typeof navigator !== 'undefined' ? navigator.userAgent : 'unknown',
  });
}

/**
 * Whether client Sentry is initialized.
 * @returns {boolean}
 */
export function isClientSentryInitialized() {
  return clientInitialized;
}

/**
 * Whether diagnostics are enabled in the current environment.
 * @returns {boolean}
 */
export function isDiagnosticsEnabled() {
  return diagnosticsEnabled;
}

export { Sentry };

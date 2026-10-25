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
 * Loads the Google Maps JavaScript API once per page, on first use. Google's
 * `gm_authFailure` (key refused) reaches every `onAuthFailure` listener.
 */

import { msg } from '../../../../i18n/index.js';

const SCRIPT_ORIGIN = 'https://maps.googleapis.com';
const READY_CALLBACK = '__gevGoogleMapsReady';
/** The page's one script load, shared by every loader on it. */
const PAGE_LOAD = Symbol.for('gev.googleMapsLoad');

/**
 * @param {{getApiKey: () => string|null|undefined, getLanguage?: () => string|null|undefined, document?: Document, global?: object}} options
 *   `getLanguage` names the UI language; Google's own controls (Terms,
 *   Report a problem) follow it. English adds nothing, as before.
 */
export function createMapsLoader({
  getApiKey,
  getLanguage,
  document = globalThis.document,
  global = globalThis,
}) {
  let authFailed = false;
  let authHandlerInstalled = false;
  const authListeners = new Set();

  /** Once per loader: a retry must not wrap its own handler. */
  function installAuthHandler() {
    if (authHandlerInstalled) return;
    authHandlerInstalled = true;
    const previous = global.gm_authFailure;
    global.gm_authFailure = () => {
      authFailed = true;
      for (const listener of [...authListeners]) {
        try {
          listener();
        } catch {
          /* a listener's error is its own */
        }
      }
      if (typeof previous === 'function') previous();
    };
  }

  function load() {
    const key = getApiKey?.();
    if (!key)
      return Promise.reject(new Error(msg('GOOGLE_MAPS_API_KEY is not set')));
    installAuthHandler();
    if (global[PAGE_LOAD]) return global[PAGE_LOAD];
    if (global.google?.maps?.importLibrary)
      return Promise.resolve(global.google.maps);
    const loading = new Promise((resolve, reject) => {
      global[READY_CALLBACK] = () => {
        delete global[READY_CALLBACK];
        resolve(global.google.maps);
      };
      const script = document.createElement('script');
      script.async = true;
      const params = new URLSearchParams({
        key,
        v: 'weekly',
        loading: 'async',
        callback: READY_CALLBACK,
      });
      const language = getLanguage?.();
      if (language && language !== 'en') params.set('language', language);
      script.src = `${SCRIPT_ORIGIN}/maps/api/js?${params}`;
      script.onerror = () => {
        if (global[PAGE_LOAD] === loading) delete global[PAGE_LOAD];
        script.remove();
        delete global[READY_CALLBACK];
        reject(new Error(msg('The Google Maps JavaScript API could not load')));
      };
      document.head.append(script);
    });
    global[PAGE_LOAD] = loading;
    return loading;
  }

  return {
    async importLibrary(name) {
      const maps = await load();
      return maps.importLibrary(name);
    },
    authFailed: () => authFailed,
    onAuthFailure(listener) {
      authListeners.add(listener);
      return () => authListeners.delete(listener);
    },
  };
}

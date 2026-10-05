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
 * Local composition of tool services: Core's default services, pointed at a
 * running God's Eye View server's `/api` routes.
 */

import { readFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { createToolServices } from '../../src/tools/services.js';

// Bundled data some sources read by module-relative URL.
const BUNDLED_DATA = new URL('../../src/data/local_data/', import.meta.url);

export const DEFAULT_API_BASE = 'http://localhost:4173';

/**
 * Resolve the sources' relative `/api/...` requests against `apiBase`, and
 * serve `file:` URLs inside the bundled data directory from disk, as a
 * browser would load those module-relative assets.
 */
export function createApiFetch({
  apiBase = DEFAULT_API_BASE,
  fetchImpl = (...args) => globalThis.fetch(...args),
} = {}) {
  const base = new URL(apiBase);
  if (!['http:', 'https:'].includes(base.protocol))
    throw new TypeError(`apiBase must be an http(s) URL: ${apiBase}`);
  return (input, init) => {
    const url = String(input instanceof Request ? input.url : input);
    if (url.startsWith('file:')) return readBundled(url);
    return fetchImpl(
      typeof input === 'string' && input.startsWith('/')
        ? new URL(input, base)
        : input,
      init,
    );
  };
}

async function readBundled(url) {
  const href = new URL(url).href;
  if (!href.startsWith(BUNDLED_DATA.href) || href.includes('/../'))
    return new Response(null, { status: 404 });
  try {
    const body = await readFile(fileURLToPath(href));
    return new Response(body, {
      headers: {
        'Content-Type': href.endsWith('.json')
          ? 'application/json'
          : 'application/octet-stream',
      },
    });
  } catch {
    return new Response(null, { status: 404 });
  }
}

/** Construct every service Core's tools read, backed by the local server. */
export function createLocalToolServices(options = {}) {
  return createToolServices({
    fetchImpl: createApiFetch(options),
    appUrl: options.apiBase ?? DEFAULT_API_BASE,
    panelKey: options.panelKey,
  });
}

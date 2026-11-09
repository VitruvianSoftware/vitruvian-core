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

import assert from 'node:assert/strict';
import { EventEmitter } from 'node:events';
import { inaturalistProxy } from './observations.js';

export const NOW = Date.parse('2026-11-04T18:05:00Z');

/** Mount the proxy over synthetic HTTP objects, without opening a socket. */
export function installInatProxy(
  defaultUrl,
  options = {},
  hook = 'configureServer',
) {
  let handler;
  const plugin = inaturalistProxy({
    now: () => NOW,
    cacheDir: null,
    queueOptions: { intervalMs: 0, windowMs: 0 },
    warn() {},
    ...options,
  });
  assert.equal(plugin.name, 'inaturalist');
  assert.equal(typeof plugin.configureServer, 'function');
  assert.equal(typeof plugin.configurePreviewServer, 'function');
  plugin[hook]({
    middlewares: {
      use(mount, callback) {
        assert.equal(mount, '/api/inaturalist');
        handler = callback;
      },
    },
  });
  return async (
    url = defaultUrl,
    { method = 'GET', peer = 'local', headers = {}, signal } = {},
  ) => {
    const res = Object.assign(new EventEmitter(), {
      headers: {},
      writeHead(status, headers) {
        this.status = status;
        Object.assign(this.headers, headers);
      },
      setHeader(key, value) {
        this.headers[key] = value;
      },
      end(value) {
        this.status ??= this.statusCode;
        this.body = JSON.parse(value);
      },
    });
    const abort = () => {
      res.destroyed = true;
      res.emit('close');
    };
    signal?.addEventListener('abort', abort, { once: true });
    try {
      await handler(
        Object.assign(new EventEmitter(), {
          url,
          method,
          headers,
          socket: { remoteAddress: peer },
        }),
        res,
      );
    } finally {
      signal?.removeEventListener('abort', abort);
    }
    return res;
  };
}

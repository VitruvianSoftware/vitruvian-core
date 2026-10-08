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
 * Preloaded into the server under test (`node --import`): every outbound
 * request fails at once instead of reaching the internet, so a route's answer
 * comes from this server alone and the test stays hermetic.
 */
import dns from 'node:dns';
import http from 'node:http';
import https from 'node:https';
import net from 'node:net';
import { syncBuiltinESMExports } from 'node:module';

const refused = () => new Error('network disabled under test');

globalThis.fetch = async () => {
  throw new TypeError('fetch failed', { cause: refused() });
};
globalThis.WebSocket = class {
  constructor() {
    throw refused();
  }
};
for (const transport of [http, https]) {
  transport.request = () => {
    throw refused();
  };
  transport.get = transport.request;
}
// The server's own listen() resolves its bind address; names of other hosts
// never resolve.
const local = (host) => net.isIP(String(host)) !== 0 || host === 'localhost';
const { lookup } = dns;
const { lookup: lookupAsync } = dns.promises;
dns.lookup = (host, options, callback) => {
  if (local(host)) return lookup(host, options, callback);
  (typeof options === 'function' ? options : callback)(refused());
};
dns.promises.lookup = async (host, options) => {
  if (local(host)) return lookupAsync(host, options);
  throw refused();
};
syncBuiltinESMExports();

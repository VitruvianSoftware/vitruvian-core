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
 * Treat an unavailable Google Maps tile-token endpoint as a supported, silent
 * outcome. Install after real token providers and before the unknown-API 404.
 */
export function googleTokenUnavailablePlugin() {
  const install = (server) => {
    server.middlewares.use((req, res, next) => {
      const pathname = String(req.url || '').split('?')[0];
      if (
        (req.method !== 'GET' && req.method !== 'HEAD') ||
        pathname !== '/api/google/tiles-token'
      ) {
        next();
        return;
      }

      res.writeHead(204, { 'Cache-Control': 'no-store' });
      res.end();
    });
  };

  return {
    name: 'google-token-unavailable',
    configureServer: install,
    configurePreviewServer: install,
  };
}

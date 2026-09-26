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

import { defaultSourceRoot } from './common/source-root.js';
import { handleHudSummary } from './openai/hud-summary.js';
import { createDebugLogHandler } from './openai/debug-log.js';
import { createRealtimeTokenHandler } from './openai/realtime.js';

/**
 * Vite plugin: OpenAI Realtime ephemeral client secret.
 *
 * Keeps OPENAI_API_KEY server-side while the browser connects to the
 * Realtime API over WebRTC with a short-lived secret.
 */
function openAiRealtimeProxy({
  sourceRoot = defaultSourceRoot,
  annotationGuidance,
  realtime = {},
} = {}) {
  function install(middlewares) {
    middlewares.use('/api/openai/hud-summary', handleHudSummary);

    middlewares.use(
      '/api/realtime/debug-log',
      createDebugLogHandler({ sourceRoot }),
    );

    middlewares.use(
      '/api/realtime/token',
      createRealtimeTokenHandler({ ...realtime, annotationGuidance }),
    );
  }

  return {
    name: 'openai-realtime-proxy',
    configureServer(server) {
      install(server.middlewares);
    },
    configurePreviewServer(server) {
      install(server.middlewares);
    },
  };
}

export { openAiRealtimeProxy };

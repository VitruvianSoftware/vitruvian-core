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
 * Capture the exact Realtime session config production mints.
 *
 * Rather than re-typing the session fields, this drives the production token
 * handler (`server/providers/openai/realtime.js`) with a fake upstream fetch
 * and returns the body it would have POSTed to OpenAI. Instructions, tools,
 * tool_choice, reasoning, and truncation therefore cannot drift from what a
 * real GEV mic session receives.
 */
import { createRealtimeTokenHandler } from '../../server/providers/openai/realtime.js';
import { realtimeInstructions } from '../../server/providers/openai/instructions.js';
import { GEV_REALTIME_TOOLS } from '../../server/providers/openai/tools.js';

export { realtimeInstructions, GEV_REALTIME_TOOLS };

/** Return production's `{ session: {...} }` client-secret body for `model`. */
export async function captureProductionSession(model) {
  let captured = null;
  const handler = createRealtimeTokenHandler({
    resolveApiKey: () => 'bench-placeholder',
    models: { standard: model, mini: model },
    fetchImpl: async (_url, init) => {
      captured = JSON.parse(init.body);
      return new Response('{}', { status: 200, headers: { 'content-type': 'application/json' } });
    },
  });
  const res = {
    statusCode: 0,
    headers: {},
    setHeader(k, v) { this.headers[k] = v; },
    end() {},
  };
  await handler({ method: 'POST', url: '/api/realtime/token', headers: {}, socket: {} }, res);
  if (!captured?.session) throw new Error('production token handler did not produce a session config');
  return captured.session;
}

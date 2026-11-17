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

import test from 'node:test';
import assert from 'node:assert/strict';
import { createVesselSource } from './standalone.js';

const answering = (status, payload) => async () => ({
  ok: status < 400,
  status,
  headers: { get: () => null },
  json: async () => payload,
});

test('a vessels server with no AISStream key refuses as key-required, a down feed as unavailable', async () => {
  const keyless = createVesselSource({
    fetchImpl: answering(503, { status: 'missing-key' }),
  });
  await assert.rejects(keyless.getSnapshot(), {
    code: 'key-required',
    message: 'AISSTREAM_API_KEY not set',
  });
  const down = createVesselSource({
    fetchImpl: answering(503, { status: 'error' }),
  });
  await assert.rejects(down.getSnapshot(), {
    code: 'unavailable',
    message: 'feed down',
  });
});

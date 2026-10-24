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
import { fetchCmrPages } from './catalog.js';
const item = (id) => ({
  meta: { 'concept-id': id },
  umm: {
    TemporalExtent: {
      RangeDateTime: { BeginningDateTime: '2026-09-18T12:00:00Z' },
    },
  },
});
test('discarded rows do not turn a full CMR page into a final page', async () => {
  let calls = 0;
  const result = await fetchCmrPages({
    product: 'S30',
    url: 'fixture',
    fetchImpl: async () => {
      calls++;
      const items =
        calls === 1
          ? Array.from({ length: 200 }, (_, i) =>
              i === 0 ? {} : item(String(i)),
            )
          : [item('last')];
      return Response.json(
        { hits: 201, items },
        { headers: { 'CMR-Search-After': `cursor-${calls}` } },
      );
    },
  });
  assert.equal(calls, 2);
  assert.equal(result.granules.length, 200);
  assert.equal(result.granules.at(-1).id, 'last');
  assert.equal(result.truncated, false);
});
test('a non-page-multiple limit never returns more admitted records than its budget', async () => {
  let calls = 0;
  const result = await fetchCmrPages({
    product: 'S30',
    url: 'fixture',
    maxRecords: 250,
    fetchImpl: async () => {
      calls++;
      return Response.json(
        {
          hits: 1000,
          items: Array.from({ length: 200 }, (_, i) => item(`${calls}:${i}`)),
        },
        { headers: { 'CMR-Search-After': `cursor-${calls}` } },
      );
    },
  });
  assert.equal(calls, 2);
  assert.equal(result.granules.length, 250);
  assert.equal(result.truncated, true);
});
test('valid records dropped by the cap mark the result truncated even when every hit was read', async () => {
  let calls = 0;
  const result = await fetchCmrPages({
    product: 'S30',
    url: 'fixture',
    maxRecords: 250,
    fetchImpl: async () => {
      calls++;
      return Response.json(
        {
          hits: 400,
          items: Array.from({ length: 200 }, (_, i) => item(`${calls}:${i}`)),
        },
        { headers: { 'CMR-Search-After': `cursor-${calls}` } },
      );
    },
  });
  assert.equal(calls, 2);
  assert.equal(result.granules.length, 250);
  assert.equal(result.truncated, true);
});
test('malformed rows discarded under the cap leave a fully examined result untruncated', async () => {
  let calls = 0;
  const result = await fetchCmrPages({
    product: 'S30',
    url: 'fixture',
    maxRecords: 250,
    fetchImpl: async () => {
      calls++;
      const items = Array.from({ length: 200 }, (_, i) =>
        calls === 2 && i >= 50 ? {} : item(`${calls}:${i}`),
      );
      return Response.json(
        { hits: 400, items },
        { headers: { 'CMR-Search-After': `cursor-${calls}` } },
      );
    },
  });
  assert.equal(calls, 2);
  assert.equal(result.granules.length, 250);
  assert.equal(result.truncated, false);
});

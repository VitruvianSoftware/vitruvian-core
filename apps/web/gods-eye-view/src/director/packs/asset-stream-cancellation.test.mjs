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
import { createAssetDirectorySource } from './source.js';
test('cancellation during the terminating read cannot return a scene asset', async () => {
  for (const cancel of [true, false]) {
    const controller = new AbortController();
    let reads = 0,
      cancelled = 0,
      released = 0;
    const source = createAssetDirectorySource({
      baseUrl: 'https://fixture.example/assets/',
      fetchImpl: async () => ({
        ok: true,
        headers: new Headers({ 'content-type': 'application/octet-stream' }),
        body: {
          getReader() {
            return {
              async read() {
                reads++;
                if (reads === 1)
                  return { done: false, value: new Uint8Array([1, 2]) };
                if (cancel) controller.abort();
                return { done: true };
              },
              async cancel() {
                cancelled++;
              },
              releaseLock() {
                released++;
              },
            };
          },
        },
      }),
    });
    const pending = source({ path: 'scene.bin', signal: controller.signal });
    if (cancel) await assert.rejects(pending, { name: 'AbortError' });
    else assert.deepEqual([...(await pending).bytes], [1, 2]);
    assert.equal(cancelled, 1);
    assert.equal(released, 1);
  }
});

test('cancellation during reader cleanup cannot return a scene asset', async () => {
  const controller = new AbortController();
  const reason = new DOMException('scene changed', 'AbortError');
  let released = 0;
  const source = createAssetDirectorySource({
    baseUrl: 'https://fixture.example/assets/',
    fetchImpl: async () => ({
      ok: true,
      headers: new Headers(),
      body: {
        getReader() {
          let reads = 0;
          return {
            async read() {
              reads++;
              return reads === 1
                ? { done: false, value: new Uint8Array([1]) }
                : { done: true };
            },
            async cancel() {
              controller.abort(reason);
            },
            releaseLock() {
              released++;
            },
          };
        },
      },
    }),
  });
  await assert.rejects(
    source({ path: 'scene.bin', signal: controller.signal }),
    (error) => error === reason,
  );
  assert.equal(released, 1);
});

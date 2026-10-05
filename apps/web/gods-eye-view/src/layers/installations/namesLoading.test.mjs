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
import { readFileSync } from 'node:fs';
import { createInstallationSource } from './source.js';
import { createIngestion } from './ingestion.js';
import { decodeOpenFreeMapMilitaryTile } from '../../sources/openFreeMap.js';
import {
  createMilitaryNamesLoader,
  loadMilitaryNames,
} from '../../data/militaryNames.js';
import { loadBundledJson } from '../../data/bundledJson.js';

const box = { south: 30.3, west: -97.8, north: 30.33, east: -97.74 };
const wide = { south: 20, west: -130, north: 60, east: -60 };
const tile = decodeOpenFreeMapMilitaryTile(
  readFileSync(
    new URL(
      '../../data/fixtures/ofm-camp-mabry-12-935-1685.pbf',
      import.meta.url,
    ),
  ),
  12,
  935,
  1685,
);
const flush = async () => {
  for (let i = 0; i < 30; i++) await Promise.resolve();
};
function deferred() {
  let resolve;
  const promise = new Promise((r) => {
    resolve = r;
  });
  return { promise, resolve };
}
function sourceWith(job) {
  return createInstallationSource({
    loadNames: () => job.promise,
    fetchImpl: async () => Response.json({ unavailable: true }),
    mapTiles: { fetchBounds: async () => ({ tiles: [tile] }), clear() {} },
  });
}

test('close polygons publish immediately while a wide consumer can cancel its independent names wait', async () => {
  const job = deferred(),
    source = sourceWith(job),
    abort = new AbortController();
  const waiting = source.getMappedSites(wide, { signal: abort.signal });
  const rejection = assert.rejects(waiting, { name: 'AbortError' });
  const payload = await source.getMappedSites(box);
  assert.ok(payload.records.length);
  assert.ok(payload.records.every((r) => r.name === 'Military area'));
  abort.abort();
  await rejection;
  job.resolve(await loadMilitaryNames());
  const enriched = await payload.enrichment;
  assert.ok(enriched.records.some((r) => r.name === 'Camp Mabry'));
});

for (const stale of [false, true])
  test(`late names ${stale ? 'cannot publish to a superseded view' : 'enrich the current published polygons'}`, async () => {
    const job = deferred(),
      source = sourceWith(job),
      publications = [];
    let currentBox = box;
    const state = {
      enabled: true,
      viewer: {},
      records: [],
      googleSearchRequested: false,
    };
    const ingestion = createIngestion({
      state,
      source,
      services: {
        render: { governorRequestRender() {} },
        ground: { resolveGroundFloorCellsBounded: async () => {} },
      },
      parts: {
        viewport: {
          loadArea: () => ({ box: currentBox, coverage: {} }),
          clearUnavailableRetry() {},
          scheduleUnavailableRetry() {},
        },
        model: { installationWithinViewport: () => true },
        rendering: {
          renderRecords: () => publications.push(state.records),
          warmInstallationFloors() {},
        },
      },
    });
    await ingestion.loadInstallations();
    assert.equal(state.loading, false);
    assert.ok(publications[0].length);
    if (stale) {
      currentBox = wide;
      state.enabled = false;
      state.abort.abort();
    }
    job.resolve(await loadMilitaryNames());
    await flush();
    assert.equal(publications.length, stale ? 1 : 2);
    if (!stale) assert.ok(state.records.some((r) => r.name === 'Camp Mabry'));
    state.abort.abort();
  });

for (const stage of ['response', 'body'])
  test(`shared names ${stage} deadline aborts and releases the retryable loader`, async (t) => {
    t.mock.timers.enable({ apis: ['setTimeout', 'Date'] });
    let calls = 0,
      signal;
    t.mock.method(globalThis, 'fetch', async (_url, options) => {
      calls++;
      signal = options.signal;
      if (calls > 1) return Response.json({ records: [], classes: [] });
      if (stage === 'response') return new Promise(() => {});
      return { ok: true, json: () => new Promise(() => {}) };
    });
    const load = createMilitaryNamesLoader({
      timeoutMs: 50,
      cooldownMs: 100,
      loadPack: (signal) =>
        loadBundledJson(new URL('https://example.test/names.json'), { signal }),
    });
    const first = load();
    assert.equal(load(), first, 'shared acquisition');
    const rejected = assert.rejects(first, { name: 'TimeoutError' });
    await flush();
    t.mock.timers.tick(51);
    await rejected;
    assert.equal(signal.aborted, true);
    await assert.rejects(load(), { name: 'TimeoutError' });
    assert.equal(calls, 1);
    t.mock.timers.tick(101);
    assert.deepEqual((await load()).records, []);
    assert.equal(calls, 2);
  });

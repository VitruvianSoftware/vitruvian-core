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
import { createLibrarySource } from './source.js';
import { libraryEntry } from './catalog.js';
import { libraryViewBox } from './manifest.js';
import { libraryImagerySpec } from './layers.js';

const tiles = libraryEntry('usgs-topo');
const view = libraryEntry('fema-usa-structures');
const entries = [tiles, view];

function serverSaying(rows, calls = []) {
  return async (url, options) => {
    calls.push({ url: String(url), options });
    if (String(url).endsWith('/catalog'))
      return Response.json({ entries: rows });
    return Response.json({ features: [], truncated: false });
  };
}

test('the server can hide an entry and route a browser-direct one through itself', async () => {
  const source = createLibrarySource({
    entries,
    storage: null,
    fetchImpl: serverSaying([
      { id: tiles.id, available: true, reason: null, fetch: 'proxied' },
      {
        id: view.id,
        available: false,
        reason: 'operator-disabled',
        listed: false,
      },
    ]),
  });
  assert.equal(source.tileTemplate(tiles), tiles.source.url);
  const { availability } = await source.getAvailability();
  assert.deepEqual(availability.get(view.id), {
    available: false,
    reason: 'operator-disabled',
    listed: false,
  });
  assert.equal(availability.get(tiles.id).available, true);
  assert.equal(
    source.tileTemplate(tiles),
    `/api/library/tile/${tiles.id}/{z}/{x}/{y}`,
  );
});

test('a routed view-bounded dataset asks the server for its snapped box, through the host fetch', async () => {
  const calls = [];
  const asked = [];
  const source = createLibrarySource({
    entries,
    storage: null,
    fetchImpl: serverSaying(
      [{ id: view.id, available: true, reason: null, fetch: 'proxied' }],
      calls,
    ),
    fetchData: async ({ entry, url }) => {
      asked.push({ entry: entry.id, url });
      return Response.json({ features: [], truncated: true });
    },
  });
  await source.getAvailability();
  const bbox = [-77.031, 38.889, -77.02, 38.9];
  const result = await source.loadDataset(view, { bbox });
  assert.equal(result.truncated, true);
  assert.deepEqual(asked, [
    {
      entry: view.id,
      url: `/api/library/data/${view.id}?bbox=${libraryViewBox(bbox).join(',')}`,
    },
  ]);
  // No box, nothing asked.
  assert.deepEqual(await source.loadDataset(view), {
    features: [],
    truncated: false,
  });
  assert.equal(asked.length, 1);
  assert.equal(calls.length, 1);
});

test("a host's tile fetch reaches the imagery spec, told the entry", async () => {
  const seen = [];
  const source = createLibrarySource({
    entries,
    storage: null,
    fetchTile: async ({ entry, url }) => {
      seen.push([entry.id, url]);
      return { missing: true };
    },
  });
  const spec = libraryImagerySpec(
    tiles,
    source.tileTemplate(tiles),
    source.tileFetch(tiles),
  );
  assert.deepEqual(await spec.fetchTile({ tile: {}, url: 'u' }), {
    missing: true,
  });
  assert.deepEqual(seen, [[tiles.id, 'u']]);
  assert.equal(
    'fetchTile' in libraryImagerySpec(tiles, tiles.source.url),
    false,
  );
  assert.equal(
    createLibrarySource({ entries, storage: null }).tileFetch(tiles),
    null,
  );
});

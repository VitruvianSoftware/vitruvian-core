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

import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { loadWarendorfSourcesFromCatalog } from '../../server/providers/cctv/sources.js';

test('Warendorf catalog registers the Marktplatz webcam on official hosts only', (t) => {
  t.mock.method(console, 'log', () => {});
  const cameras = loadWarendorfSourcesFromCatalog();
  assert.deepEqual(
    cameras.map((camera) => camera.id),
    ['warendorf-marktplatz-rathaus'],
  );
  for (const camera of cameras) {
    assert.ok(
      /^https?:\/\/(webcam\.warendorf\.de|www\.kreis-warendorf\.de)\//.test(
        camera.url,
      ),
      camera.url,
    );
    assert.equal(camera.snapshotUrl, camera.url);
    assert.equal(camera.sourceKind, 'municipal-webcam');
    assert.equal(camera.poseSource, 'curated');
    assert.match(camera.license, /^Public municipal webcam data/);
  }
});

test('Warendorf loader tolerates a missing catalog file', (t) => {
  t.mock.method(console, 'warn', () => {});
  assert.deepEqual(
    loadWarendorfSourcesFromCatalog({ sourceRoot: '/nonexistent' }),
    [],
  );
});

test('Warendorf loader skips malformed rows without throwing', (t) => {
  t.mock.method(console, 'log', () => {});
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'gev-warendorf-'));
  fs.mkdirSync(path.join(dir, 'config'));
  fs.writeFileSync(
    path.join(dir, 'config', 'cctv_sources.warendorf.json'),
    JSON.stringify([
      {
        id: { toString: null },
        url: 'https://www.kreis-warendorf.de/a.jpg',
        lat: 51.9,
        lon: 7.9,
      },
      {
        id: 'ok',
        url: 'https://www.kreis-warendorf.de/a.jpg',
        lat: 51.9,
        lon: 7.9,
      },
      {
        id: 'text-coords',
        url: 'https://www.kreis-warendorf.de/a.jpg',
        lat: '51.9',
        lon: '7.9',
      },
      {
        id: 'null-island',
        url: 'https://www.kreis-warendorf.de/a.jpg',
        lat: 0,
        lon: 0,
      },
      {
        id: 'off-host',
        url: 'https://evil.example/a.jpg',
        lat: 51.9,
        lon: 7.9,
      },
    ]),
  );
  const cameras = loadWarendorfSourcesFromCatalog({ sourceRoot: dir });
  assert.deepEqual(
    cameras.map((camera) => camera.id),
    ['ok'],
  );
});

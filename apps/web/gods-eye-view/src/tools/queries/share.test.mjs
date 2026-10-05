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

import assert from 'node:assert/strict';
import test from 'node:test';
import { composeCatalog, coreTools } from '../index.js';

test('links open the app looking straight down on the area', async () => {
  const catalog = composeCatalog({
    tools: coreTools,
    services: { app: { baseUrl: 'https://maps.example/view?x=1' } },
  });
  const result = await catalog.call('show_in_gods_eye_view', {
    area: { lat: 30.2672, lon: -97.7431, radius_km: 5 },
  });
  const url = new URL(result.data.url);
  assert.equal(
    url.origin + url.pathname + url.search,
    'https://maps.example/view?x=1',
  );
  assert.deepEqual(Object.fromEntries(new URLSearchParams(url.hash.slice(1))), {
    v: '2',
    lat: '30.2672',
    lon: '-97.7431',
    alt: '9091',
    heading: '0',
    pitch: '-90',
    roll: '0',
  });
  assert.equal(
    result.summary,
    `Open 5 km around 30.267, -97.743 in God's Eye View: ${url.href}`,
  );
});

test('altitude is bounded for tiny and planet-sized areas', async () => {
  const catalog = composeCatalog({
    tools: coreTools,
    services: { app: { baseUrl: 'http://localhost:4173/' } },
  });
  const tiny = await catalog.call('show_in_gods_eye_view', {
    area: { lat: 0, lon: 0, radius_km: 0.1 },
  });
  assert.equal(tiny.data.view.camera.altitude_m, 500);
  const world = await catalog.call('show_in_gods_eye_view', {
    area: { bbox: [-180, -85, 180, 85] },
  });
  assert.equal(world.data.view.camera.altitude_m, 15000000);
  const broken = composeCatalog({
    tools: coreTools,
    services: { app: { baseUrl: 'not a url' } },
  });
  await assert.rejects(
    broken.call('show_in_gods_eye_view', {
      area: { lat: 0, lon: 0, radius_km: 1 },
    }),
    (error) => error.code === 'unavailable',
  );
});

test('links turn on the requested layers with the app share-link codec', async () => {
  const { decodeLayerStateParams } = await import('../../data/layerState.js');
  const catalog = composeCatalog({
    tools: coreTools,
    services: { app: { baseUrl: 'http://localhost:4173/' } },
  });
  const result = await catalog.call('show_in_gods_eye_view', {
    area: { lat: 30.27, lon: -97.74, radius_km: 10 },
    layers: ['earthquakes', 'flights', 'flights'],
  });
  assert.deepEqual(result.data.view.layers, ['earthquakes', 'flights']);
  const params = new URLSearchParams(new URL(result.data.url).hash.slice(1));
  assert.deepEqual(decodeLayerStateParams(params).enabledLayerIds.sort(), [
    'earthquakes',
    'flights',
  ]);
  await assert.rejects(
    catalog.call('show_in_gods_eye_view', {
      area: { lat: 0, lon: 0, radius_km: 1 },
      layers: ['not-a-layer'],
    }),
    /must be one of/,
  );
});

test('links carry a camera, style, map and an entity to follow', async () => {
  const { viewFromParams } = await import('../../view/index.js');
  const catalog = composeCatalog({
    tools: coreTools,
    services: { app: { baseUrl: 'http://localhost:4173/' } },
  });
  const result = await catalog.call('show_in_gods_eye_view', {
    area: { lat: 25, lon: 121, radius_km: 200 },
    camera: { pitch_deg: -40, heading_deg: 350 },
    layers: ['ais-live-vessels'],
    style: 'thermal',
    map: 'esri-imagery',
    follow: { kind: 'military_aircraft', id: 'AE1234' },
  });
  const params = new URLSearchParams(new URL(result.data.url).hash.slice(1));
  assert.equal(params.get('style'), 'flir');
  assert.deepEqual(viewFromParams(params), result.data.view);
  assert.deepEqual(result.data.view.layers, ['ais-live-vessels', 'military']);
  assert.deepEqual(result.data.view.follow, {
    kind: 'military_aircraft',
    id: 'ae1234',
  });
  assert.equal(result.data.view.camera.pitch_deg, -40);
  const camera = await catalog.call('show_in_gods_eye_view', {
    camera: { lat: 48.8584, lon: 2.2945, altitude_m: 1200, pitch_deg: -30 },
  });
  assert.equal(camera.data.view.camera.altitude_m, 1200);
  assert.match(camera.summary, /^Open 48\.858, 2\.295 in God's Eye View: /);
  await assert.rejects(
    catalog.call('show_in_gods_eye_view', { layers: ['flights'] }),
    /Give a view, an area, or a camera with lat and lon/,
  );
});

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
import { CITY_BY_ID } from './registry.js';
import { createModel } from './model.js';
import { createViewport } from './viewport.js';
import { isAllowedGbfsHost, isAllowedGbfsPath } from '../../data/gbfsSource.js';

// Each Bike Itaú city's PBSC host, and the station farthest from its
// registered centre in the live feed (checked 2026-10-15).
const CITIES = {
  'sao-paulo-bike-itau': {
    host: 'saopaulo.publicbikesystem.net',
    stations: [{ name: '260 - P3', lat: -23.568235, lon: -46.740715 }],
  },
  'rio-de-janeiro-bike-itau': {
    host: 'riodejaneiro.publicbikesystem.net',
    stations: [{ name: '293 - Praia da Macumba', lat: -23.03135, lon: -43.479584 }],
  },
  'salvador-bike-itau': {
    host: 'salvador.publicbikesystem.net',
    stations: [{ name: '49 - Stella Maris', lat: -12.93645, lon: -38.32701 }],
  },
  'recife-bike-itau': {
    host: 'recife.publicbikesystem.net',
    stations: [{ name: '69 - Praia de Piedade', lat: -8.186205, lon: -34.918371 }],
  },
  'porto-alegre-bike-itau': {
    host: 'portoalegre.publicbikesystem.net',
    stations: [{ name: '72 - Avenida Tramandaí', lat: -30.135915, lon: -51.22684 }],
  },
  'brasilia-bike-itau': {
    host: 'brasilia.publicbikesystem.net',
    stations: [{ name: "60 - Parque Olhos d'Água", lat: -15.7431, lon: -47.88667 }],
  },
  'curitiba-bike-itau': {
    host: 'curitiba.publicbikesystem.net',
    stations: [{ name: '42 - Terminal Portão', lat: -25.476885, lon: -49.292608 }],
  },
};

// The production range check, with no viewer or fetches behind it.
const parts = { model: createModel({ state: {}, services: {}, parts: {}, source: null }) };
const { computeInRangeCities } = createViewport({
  state: {},
  services: { render: { governorRequestRender() {} } },
  parts,
  source: null,
});

test('the Bike Itaú systems are registered and readable through the proxy', () => {
  for (const [id, expected] of Object.entries(CITIES)) {
    const city = CITY_BY_ID.get(id);
    assert.ok(city, `${id} is registered`);
    assert.equal(city.provider, 'Bike Itaú');
    assert.deepEqual(city.hosts, [expected.host]);
    for (const feed of [city.stationInformationUrl, city.stationStatusUrl]) {
      const url = new URL(feed);
      assert.ok(isAllowedGbfsHost(url.hostname), `${id} host ${url.hostname}`);
      assert.ok(isAllowedGbfsPath(url.pathname), `${id} path ${url.pathname}`);
    }
  }
});

test('a camera over each outermost station activates its system', () => {
  for (const [id, expected] of Object.entries(CITIES)) {
    for (const station of expected.stations) {
      assert.ok(
        computeInRangeCities({ lat: station.lat, lon: station.lon }).has(id),
        `${station.name} activates ${id}`,
      );
    }
  }
});

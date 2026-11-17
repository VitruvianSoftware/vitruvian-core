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

// src/layers/vessels/photos.test.mjs — a selected vessel's photo is asked for
// once per MMSI; a miss is final and a failure is retried only after a pause.
import test from 'node:test';
import assert from 'node:assert/strict';
import { createPhotos } from './photos.js';

const ANSWER = Object.freeze({
  mmsi: '366999709',
  photos: [
    {
      urls: {
        mmsi: 'https://openvesselphotos.org/v1/mmsi/366999709/photos/1.jpg',
      },
      credit: 'Gordon Leggett',
      licenceName: 'CC BY 4.0',
      width: 1600,
      height: 1200,
    },
  ],
});

const settle = () => new Promise((resolve) => setImmediate(resolve));

function fixture(answer) {
  const asked = [];
  const source = {
    getSnapshot() {},
    async getEnrichment(query) {
      asked.push(query);
      return answer(query);
    },
  };
  const photos = createPhotos({ vesselState: { _source: source } });
  return { photos, asked };
}

test('a selected vessel is asked once and shows its checked photo', async () => {
  const { photos, asked } = fixture(() => ANSWER);
  const record = { id: 'v1', mmsi: '366999709' };
  photos.requestVesselPhoto(record);
  photos.requestVesselPhoto(record);
  await settle();
  photos.requestVesselPhoto(record);
  assert.deepEqual(asked, [{ kind: 'photo', id: '366999709' }]);
  assert.deepEqual(photos.vesselPhoto(record), {
    src: 'https://openvesselphotos.org/v1/mmsi/366999709/photos/1.jpg?size=800',
    width: 800,
    height: 600,
    photographer: 'Gordon Leggett',
    licence: 'CC BY 4.0',
    link: 'https://openvesselphotos.org/vessels/mmsi/366999709',
  });
});

test('a vessel without a valid MMSI, or a source without lookups, is never asked', async () => {
  const { photos, asked } = fixture(() => ANSWER);
  photos.requestVesselPhoto({ id: 'v1', mmsi: '' });
  photos.requestVesselPhoto({ id: 'v2', mmsi: '12345' });
  await settle();
  assert.equal(asked.length, 0);
  const bare = createPhotos({ vesselState: { _source: { getSnapshot() {} } } });
  bare.requestVesselPhoto({ id: 'v3', mmsi: '366999709' });
  assert.equal(bare.vesselPhoto({ mmsi: '366999709' }), null);
});

test('a miss is final; a failure is asked again only after the pause', async () => {
  let fail = true;
  const { photos, asked } = fixture(({ id }) => {
    if (id === '111111111') return { mmsi: id, photos: [] };
    if (fail) throw new Error('down');
    return ANSWER;
  });
  const missing = { mmsi: '111111111' };
  const flaky = { mmsi: '366999709' };
  photos.requestVesselPhoto(missing);
  photos.requestVesselPhoto(flaky, 0);
  await settle();
  photos.requestVesselPhoto(missing);
  photos.requestVesselPhoto(flaky, Date.now() + 1000);
  assert.equal(asked.length, 2);
  fail = false;
  photos.requestVesselPhoto(flaky, Date.now() + 10 * 60 * 1000);
  await settle();
  assert.equal(asked.length, 3);
  assert.equal(photos.vesselPhoto(missing), null);
  assert.equal(photos.vesselPhoto(flaky).photographer, 'Gordon Leggett');
});

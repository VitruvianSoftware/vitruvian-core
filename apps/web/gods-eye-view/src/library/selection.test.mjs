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
import {
  LIBRARY_STORAGE_KEY,
  decodeLibraryParam,
  encodeLibraryParam,
  nextLibraryToken,
  normalizeLibrarySelection,
  readLibraryLedger,
  readStoredLibrarySelection,
  writeStoredLibrarySelection,
} from './selection.js';

const rows = [
  ['nasa-eonet-events', '00'],
  ['eia-power-plants', '01'],
];

test('the ledger maps ids to two-character tokens both ways', () => {
  const ledger = readLibraryLedger(rows);
  assert.equal(ledger.ok, true);
  assert.equal(ledger.tokenById.get('eia-power-plants'), '01');
  assert.equal(ledger.idByToken.get('00'), 'nasa-eonet-events');
  assert.equal(readLibraryLedger([...rows, ['other-entry', '01']]).ok, false);
  assert.equal(readLibraryLedger([['bad-token', 'a']]).ok, false);
  assert.equal(nextLibraryToken(rows), '02');
  assert.equal(nextLibraryToken([]), '00');
  assert.equal(nextLibraryToken([['x-y-z', 'zz']]), null);
});

test('lib= round-trips the switched-on entries and skips unknown tokens', () => {
  const ledger = readLibraryLedger(rows);
  const params = new URLSearchParams('lat=1');
  encodeLibraryParam(
    params,
    ['eia-power-plants', 'nasa-eonet-events', 'missing-entry'],
    ledger.tokenById,
  );
  assert.equal(params.get('lib'), '01.00');
  assert.deepEqual(decodeLibraryParam(params, ledger.idByToken), [
    'eia-power-plants',
    'nasa-eonet-events',
  ]);
  assert.deepEqual(
    decodeLibraryParam(new URLSearchParams('lib=zz.01.!!'), ledger.idByToken),
    ['eia-power-plants'],
  );
  assert.equal(
    decodeLibraryParam(new URLSearchParams('lat=1'), ledger.idByToken),
    null,
  );
  encodeLibraryParam(params, [], ledger.tokenById);
  assert.equal(params.has('lib'), false);
});

test('a selection keeps on within added and drops unknown ids', () => {
  const allowed = new Set(['a-entry', 'b-entry']);
  assert.deepEqual(
    normalizeLibrarySelection(
      {
        added: ['a-entry', 'a-entry', 'zzz-unknown', 7],
        on: ['b-entry', 'a-entry'],
      },
      allowed,
    ),
    { added: ['a-entry'], on: ['a-entry'] },
  );
});

test('storage failures read as empty and never throw', () => {
  const throwing = {
    getItem() {
      throw new Error('blocked');
    },
    setItem() {
      throw new Error('blocked');
    },
  };
  assert.deepEqual(readStoredLibrarySelection(throwing), { added: [], on: [] });
  assert.equal(
    writeStoredLibrarySelection(throwing, { added: ['a-entry'] }),
    false,
  );
  const store = new Map();
  const storage = {
    getItem: (key) => store.get(key) ?? null,
    setItem: (key, value) => store.set(key, value),
  };
  writeStoredLibrarySelection(storage, { added: ['a-entry'], on: ['a-entry'] });
  assert.deepEqual(JSON.parse(store.get(LIBRARY_STORAGE_KEY)), {
    added: ['a-entry'],
    on: ['a-entry'],
  });
  store.set(LIBRARY_STORAGE_KEY, '{not json');
  assert.deepEqual(readStoredLibrarySelection(storage), { added: [], on: [] });
});

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
import { readdirSync, readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import {
  LIBRARY_ENTRIES,
  LIBRARY_LEDGER,
  LIBRARY_MANIFESTS,
} from './catalog.js';
import { readLibraryLedger } from './selection.js';

const here = path.dirname(fileURLToPath(import.meta.url));

test('every manifest file is imported, named after its id', () => {
  const files = readdirSync(path.join(here, 'entries'))
    .filter((name) => name.endsWith('.json'))
    .sort();
  assert.deepEqual(
    files,
    LIBRARY_MANIFESTS.map(({ id }) => `${id}.json`).sort(),
  );
  for (const file of files) {
    const raw = JSON.parse(
      readFileSync(path.join(here, 'entries', file), 'utf8'),
    );
    assert.equal(`${raw.id}.json`, file);
  }
});

test('every switchable entry owns a permanent share token', () => {
  const ledger = readLibraryLedger(LIBRARY_LEDGER);
  assert.deepEqual(ledger.errors, []);
  for (const entry of LIBRARY_ENTRIES.filter(({ kind }) => kind !== 'pack'))
    assert.ok(ledger.tokenById.has(entry.id), `${entry.id} has no token`);
  // Packs are switched by their host, never by a share link.
  for (const entry of LIBRARY_ENTRIES.filter(({ kind }) => kind === 'pack'))
    assert.equal(ledger.tokenById.has(entry.id), false, entry.id);
});

test('nothing in the library is bundled: every source is a live https upstream', () => {
  for (const entry of LIBRARY_ENTRIES) {
    assert.match(entry.source.url, /^https:\/\//, entry.id);
    assert.ok(entry.licence.name && entry.licence.url, entry.id);
    assert.ok(entry.attribution.text, entry.id);
  }
});

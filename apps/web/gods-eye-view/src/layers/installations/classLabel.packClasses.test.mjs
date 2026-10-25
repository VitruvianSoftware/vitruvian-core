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

// Every class the bundled OSM names pack can put on a record has a
// catalog entry, so the selected card shows it in the UI language.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { setLocale, getCatalog } from '../../i18n/index.js';
import { installationClassLabel } from './classLabel.js';

const pack = JSON.parse(
  readFileSync(
    new URL(
      '../../data/local_data/osm_military_names/names.json',
      import.meta.url,
    ),
    'utf8',
  ),
);

setLocale('en');
const englishLabel = Object.fromEntries(
  pack.classes.map((c) => [c, installationClassLabel(c)]),
);

for (const locale of ['es', 'ru']) {
  test(`every names-pack class is in the ${locale} catalog`, () => {
    const catalog = getCatalog(locale);
    const missing = pack.classes.filter(
      (c) => catalog[`installation class|${englishLabel[c]}`] === undefined,
    );
    assert.deepEqual(
      missing,
      [],
      `no ${locale} entry for: ${missing.join(', ')}`,
    );
  });
}

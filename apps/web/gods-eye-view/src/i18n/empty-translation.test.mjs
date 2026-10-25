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

// An empty or blank translation must not count as done.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  checkCatalog,
  extractMessages,
  readCatalog,
} from '../../scripts/i18n.mjs';
import { getCatalog, setLocale, t, tn, translateKnown } from './index.js';

const messages = extractMessages();
const EMPTY = 'DISCONNECT';
const BLANK = 'CONTACT LOST · LAST KNOWN READOUT · NOT AN ALL-CLEAR';

for (const locale of ['es', 'ru']) {
  test(`${locale}: checkCatalog rejects an empty or blank translation`, () => {
    const catalog = { ...readCatalog(locale), [EMPTY]: '', [BLANK]: '  ' };
    const { errors } = checkCatalog(locale, catalog, messages);
    assert.ok(
      errors.some((e) => e.includes(`"${EMPTY}"`)),
      'empty string passes the check',
    );
    assert.ok(
      errors.some((e) => e.includes(`"${BLANK}"`)),
      'blank string passes the check',
    );
  });
}

test('t() and translateKnown() fall back to English for an empty entry', () => {
  const es = getCatalog('es');
  const saved = es[EMPTY];
  es[EMPTY] = '';
  setLocale('es');
  try {
    assert.equal(t(EMPTY), EMPTY);
    assert.equal(translateKnown(EMPTY), EMPTY);
  } finally {
    es[EMPTY] = saved;
    setLocale('en');
  }
});

test('tn() skips an empty plural form', () => {
  const es = getCatalog('es');
  const KEY = '{count} INPUTS UNKNOWN';
  const saved = es[KEY];
  setLocale('es');
  try {
    es[KEY] = { ...saved, one: ' ' };
    assert.equal(
      tn(1, '{count} INPUT UNKNOWN', KEY),
      saved.other.replace('{count}', '1'),
    );
    es[KEY] = { one: '', many: '', other: '' };
    assert.equal(tn(1, '{count} INPUT UNKNOWN', KEY), '1 INPUT UNKNOWN');
    assert.equal(tn(3, '{count} INPUT UNKNOWN', KEY), '3 INPUTS UNKNOWN');
  } finally {
    es[KEY] = saved;
    setLocale('en');
  }
});

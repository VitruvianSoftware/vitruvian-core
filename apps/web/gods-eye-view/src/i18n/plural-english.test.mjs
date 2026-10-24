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
import {
  checkCatalog,
  extractMessages,
  missingTemplate,
} from '../../scripts/i18n.mjs';

// A plural entry with forms left in English is reported like a string entry.
const fixture = new Map([
  ['{count} cameras', { plural: true, one: '{count} camera' }],
  ['Save keys', { plural: false }],
]);

test('string entry left in English is reported (control)', () => {
  const { errors } = checkCatalog(
    'de',
    {
      'Save keys': 'Save keys',
      '{count} cameras': { one: 'x {count}', other: 'y {count}' },
    },
    fixture,
    new Set(),
  );
  assert.equal(errors.length, 1);
  assert.match(errors[0], /is still English/);
});

for (const [locale, entry] of [
  ['de', { one: '{count} camera', other: '{count} cameras' }],
  ['ja', { other: '{count} cameras' }],
  ['zh-CN', { other: '{count} cameras' }],
  [
    'es',
    {
      one: '{count} camera',
      many: '{count} cámaras',
      other: '{count} cameras',
    },
  ],
  [
    'ru',
    {
      one: '{count} camera',
      few: '{count} камеры',
      many: '{count} камер',
      other: '{count} cameras',
    },
  ],
]) {
  test(`${locale}: plural entry with English forms is reported`, () => {
    const { errors } = checkCatalog(
      locale,
      { 'Save keys': 'Schlüssel', '{count} cameras': entry },
      fixture,
      new Set(),
    );
    assert.ok(
      errors.some((e) => /is still English/.test(e)),
      `expected an "is still English" error, got ${JSON.stringify(errors)}`,
    );
  });
}

// The `--missing` template, pasted without edits, must fail entry by entry,
// and its plural entries carry every form the language needs.
const messages = extractMessages();
for (const locale of ['de', 'ja', 'es', 'ru']) {
  test(`${locale}: an untouched --missing template fails the check entry by entry`, () => {
    const template = missingTemplate(locale, {}, messages);
    assert.equal(Object.keys(template).length, messages.size);
    const categories = new Intl.PluralRules(locale).resolvedOptions()
      .pluralCategories;
    for (const [text, info] of messages)
      if (info.plural)
        assert.deepEqual(Object.keys(template[text]), categories, text);
    const { missing, errors } = checkCatalog(
      locale,
      template,
      messages,
      new Set(),
    );
    assert.deepEqual(missing, []);
    const accepted = [...messages.keys()].filter(
      (text) => !errors.some((error) => error.startsWith(`"${text}" `)),
    );
    assert.deepEqual(accepted, []);
  });
}

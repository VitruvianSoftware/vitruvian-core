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

// Director storage-failure notices and stop reasons must be marked for
// translation and present in every shipped catalog, so es/ru users do not
// get English toasts or Scene status lines. The stop reason itself stays
// English data (it is logged); only the status line translates it.
import { test } from 'node:test';
import assert from 'node:assert/strict';

import {
  extractMessages,
  readCatalog,
  shippedLocales,
} from '../../scripts/i18n.mjs';

const NOTICES = [
  'Scene not saved — browser storage unavailable',
  'Scene not saved — existing saved project could not be read. Export edits or import a valid file.',
  'Saved project could not be read; storage preserved. Import a valid file to resume saving.',
  'Scene not saved — {reason}',
  'Stopped',
  'Stopped (Esc)',
  'Stopped by voice',
  'Camera ownership changed',
  'Scene layer turned off',
  'Seeking scene clock',
  'Importing project',
  'Camera move interrupted',
  'Scene media timed out',
];

const messages = extractMessages();

for (const text of NOTICES) {
  test(`Director notice is marked with t()/msg(): ${text}`, () => {
    assert.ok(messages.has(text), `not marked for translation: ${text}`);
  });
  for (const locale of shippedLocales()) {
    test(`${locale} catalog translates: ${text}`, () => {
      const value = readCatalog(locale)[text];
      assert.ok(value, `missing in ${locale}.json`);
      assert.notEqual(value, text);
    });
  }
}

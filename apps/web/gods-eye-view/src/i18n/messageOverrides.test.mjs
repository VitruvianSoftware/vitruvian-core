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

import { test, afterEach } from 'node:test';
import assert from 'node:assert/strict';

import {
  onLocaleChange,
  setLocale,
  setMessageOverrides,
  t,
  tn,
  translateKnown,
} from './index.js';
import * as page from './page.js';

afterEach(() => {
  setMessageOverrides({});
  setLocale('en');
});

test('a host shows its own text for a Core message, in English and each locale', () => {
  setMessageOverrides({
    en: { 'Download scene JSON': 'Download scene file' },
    de: { 'Download scene JSON': 'Szenendatei herunterladen' },
  });
  assert.equal(t('Download scene JSON'), 'Download scene file');
  setLocale('de');
  assert.equal(t('Download scene JSON'), 'Szenendatei herunterladen');
  // A locale the host did not word shows the host's English, not Core's text.
  setLocale('fr');
  assert.equal(t('Download scene JSON'), 'Download scene file');
  // Messages it does not name stay Core's.
  assert.equal(t('Share selected scene'), 'Partager la scène sélectionnée');
});

test('overrides interpolate, take contexts and plurals, and reach translateKnown', () => {
  setMessageOverrides({
    en: {
      'Imported {file}': 'Opened {file}',
      'action|CLEAR': 'WIPE',
      '{count} cameras': { one: '{count} feed', other: '{count} feeds' },
    },
  });
  assert.equal(t('Imported {file}', { file: 'a.zip' }), 'Opened a.zip');
  assert.equal(t('CLEAR', { context: 'action' }), 'WIPE');
  assert.equal(t('CLEAR'), 'CLEAR');
  assert.equal(tn(1, '{count} camera', '{count} cameras'), '1 feed');
  assert.equal(tn(3, '{count} camera', '{count} cameras'), '3 feeds');
  assert.equal(translateKnown('Imported {file}'), 'Opened {file}');
  // English forms follow English plural rules in any locale.
  for (const locale of ['ru', 'zh-CN', 'fr']) {
    setLocale(locale);
    assert.equal(tn(1, '{count} camera', '{count} cameras'), '1 feed');
    assert.equal(tn(21, '{count} camera', '{count} cameras'), '21 feeds');
    assert.equal(tn(0, '{count} camera', '{count} cameras'), '0 feeds');
  }
});

test('an entry of the wrong kind is ignored, and Core translates', () => {
  setLocale('ru');
  const core = {
    t: t('Share selected scene'),
    tn: tn(3, '{count} camera', '{count} cameras'),
  };
  setMessageOverrides({
    en: { 'Share selected scene': {}, '{count} cameras': 'cams' },
  });
  assert.equal(t('Share selected scene'), core.t);
  assert.equal(tn(3, '{count} camera', '{count} cameras'), core.tn);
});

test('each call replaces the overrides, words listeners again, and ignores junk', () => {
  let calls = 0;
  const stop = onLocaleChange(() => calls++);
  setMessageOverrides({
    en: { EXPORT: 'SAVE' },
    xx: { EXPORT: 'no' },
    de: null,
  });
  assert.equal(t('EXPORT'), 'SAVE');
  setMessageOverrides({ en: { IMPORT: 'OPEN' } });
  assert.equal(t('EXPORT'), 'EXPORT');
  assert.equal(t('IMPORT'), 'OPEN');
  // An empty entry counts as none.
  setMessageOverrides({ en: { IMPORT: '' } });
  assert.equal(t('IMPORT'), 'IMPORT');
  assert.equal(calls, 3);
  stop();
});

test('the package entry exports the translator and the overrides', () => {
  for (const name of [
    't',
    'tn',
    'msg',
    'translateKnown',
    'setMessageOverrides',
    'formatNumber',
  ])
    assert.equal(typeof page[name], 'function', name);
});

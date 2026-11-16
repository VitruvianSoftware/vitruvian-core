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

// src/i18n/page.test.mjs — an application with its own language choice starts,
// follows and switches the page's language as the globe picker does.
import { afterEach, test } from 'node:test';
import assert from 'node:assert/strict';
import { LOCALE_STORAGE_KEY } from './locale.js';
import {
  followPageLocale,
  getLocale,
  startPageLocale,
  switchLocale,
} from './page.js';
import { setLocale } from './index.js';

afterEach(() => setLocale('en'));

function memoryStorage() {
  const data = new Map();
  return {
    data,
    getItem: (key) => data.get(key) ?? null,
    setItem: (key, value) => data.set(key, String(value)),
  };
}

function page(elements = []) {
  return {
    documentElement: { lang: '', dir: '' },
    querySelectorAll: (selector) =>
      selector === '[data-i18n]' ? elements : [],
  };
}

/** A data-i18n element, as applyDocumentTranslations reads one. */
function marked(text) {
  return {
    textContent: text,
    hasAttribute: (name) => name === 'data-i18n',
    getAttribute: () => null,
  };
}

test('the page starts in ?lang=, else the stored choice, with lang and dir set', () => {
  const doc = page();
  const storage = memoryStorage();
  storage.setItem(LOCALE_STORAGE_KEY, 'de');
  assert.equal(
    startPageLocale(doc, {
      location: { search: '?lang=ar' },
      storage,
      languages: ['ru'],
    }),
    'ar',
  );
  assert.equal(getLocale(), 'ar');
  assert.deepEqual(doc.documentElement, { lang: 'ar', dir: 'rtl' });
  assert.equal(
    startPageLocale(doc, { location: { search: '' }, storage, languages: [] }),
    'de',
  );
  assert.deepEqual(doc.documentElement, { lang: 'de', dir: 'ltr' });
});

test("the page's data-i18n markup is in its language from the start", () => {
  const close = marked('Close');
  startPageLocale(page([close]), {
    location: { search: '?lang=de' },
    storage: memoryStorage(),
    languages: [],
  });
  assert.equal(close.textContent, 'Schließen');
});

test('a switch is stored, drops ?lang, and the followed page takes it', () => {
  const doc = page();
  const stop = followPageLocale(doc);
  const storage = memoryStorage();
  const replaced = [];
  const options = {
    location: { href: 'https://example.test/?lang=fr#view' },
    history: { replaceState: (_s, _t, url) => replaced.push(url) },
    storage,
  };
  assert.equal(switchLocale('he', options), 'switched');
  assert.equal(getLocale(), 'he');
  assert.equal(storage.data.get(LOCALE_STORAGE_KEY), 'he');
  assert.deepEqual(replaced, ['https://example.test/#view']);
  assert.deepEqual(doc.documentElement, { lang: 'he', dir: 'rtl' });
  stop();
  switchLocale('ja', options);
  assert.deepEqual(doc.documentElement, { lang: 'he', dir: 'rtl' });
});

test('choosing the active language, or one that falls back to it, changes nothing', () => {
  const storage = memoryStorage();
  const options = {
    location: { href: 'https://example.test/' },
    history: { replaceState() {} },
    storage,
  };
  assert.equal(switchLocale('en', options), 'unchanged');
  assert.equal(switchLocale('xx', options), 'unchanged');
  assert.equal(storage.data.size, 0);
  assert.equal(switchLocale('pt-BR', options), 'switched');
  assert.equal(getLocale(), 'pt');
  assert.equal(switchLocale('pt', options), 'unchanged');
});

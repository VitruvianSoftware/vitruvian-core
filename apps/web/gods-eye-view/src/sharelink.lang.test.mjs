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

// A copied share link must not carry the sender's ?lang override: on the
// recipient's side ?lang would beat their own stored choice.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { ShareLinkManager } from './sharelink.js';
import { resolveLocale } from './i18n/locale.js';
import { persistLocaleAndReload } from './i18n/index.js';

function makeManager(href) {
  globalThis.window = { location: { href, hash: new URL(href).hash } };
  globalThis.history = { replaceState() {} };
  const viewer = {
    camera: {
      changed: { addEventListener() {} },
      positionCartographic: { latitude: 0, longitude: 0, height: 1000 },
      heading: 0,
      pitch: -Math.PI / 2,
      roll: 0,
    },
  };
  return new ShareLinkManager(viewer);
}

function installClipboard(writeText) {
  Object.defineProperty(globalThis, 'navigator', {
    configurable: true,
    value: { clipboard: { writeText } },
  });
}

test('the copied link does not carry the sender ?lang override', async () => {
  let copied = null;
  installClipboard(async (url) => {
    copied = url;
  });
  const manager = makeManager('https://gev.example/?lang=ru#v=2&lat=10&lon=20');
  assert.equal(await manager.copyLink({ nowMs: 1_000_000 }), true);
  const link = new URL(copied);
  assert.equal(link.searchParams.get('lang'), null, `copied link: ${copied}`);

  const store = new Map([['gev:locale:v1', 'es']]);
  const recipient = resolveLocale({
    location: { search: link.search },
    storage: { getItem: (k) => store.get(k) ?? null },
    languages: ['en-US'],
  });
  assert.equal(recipient, 'es');
});

test('with storage blocked the language picker keeps the choice in ?lang', () => {
  let href = 'https://gev.example/#v=2';
  const location = {
    get href() {
      return href;
    },
    assign(next) {
      href = next;
    },
    reload() {},
  };
  const history = {
    replaceState: (_s, _t, url) => {
      href = url;
    },
  };
  const blocked = {
    setItem() {
      throw new Error('blocked');
    },
  };
  persistLocaleAndReload('ru', { location, history, storage: blocked });
  // Storage blocked: the choice survives only in ?lang.
  assert.equal(new URL(href).searchParams.get('lang'), 'ru');
});

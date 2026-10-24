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

// KartaView texts are English data (msg() in providers/kartaview/) shown
// through translateKnown, so each needs an entry in every catalog.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { setLocale, translateKnown } from './index.js';

const MESSAGES = [
  // kartaview/policy.js
  'KartaView is rate-limiting requests — they resume on their own',
  'KartaView’s photos here are archived and cannot be shown',
  'KartaView did not filter this area in time — move the map to ask again',
  'None of KartaView’s photos here pass the imagery filter',
  // kartaview/source.js
  'KartaView did not answer in time — try again',
  'KartaView could not be reached — check the network',
  'KartaView sent an answer that could not be read',
  'KartaView is rate-limiting requests',
  'KartaView is rate-limiting requests — try again in a moment',
  'KartaView sent too much data',
  'KartaView has no such photo',
  // kartaview/viewer.js, index.js
  'The KartaView photo could not be loaded',
  'KartaView has no position for this photo',
];

for (const locale of ['es', 'ru']) {
  test(`KartaView provider messages are translated in ${locale}`, () => {
    setLocale(locale);
    try {
      const untranslated = MESSAGES.filter((m) => translateKnown(m) === m);
      assert.deepEqual(untranslated, []);
    } finally {
      setLocale('en');
    }
  });
}

// kartaview/source.js refusals with a number in them: English data, shown
// through placeholder entries by the Street Level panel and the layer panel.
test('KartaView HTTP and refusal codes keep their number in every language', async () => {
  const { translateStreetLevelError } =
    await import('../ui/streetLevelPresentation.js');
  const http = 'KartaView answered HTTP 503';
  const refused = 'KartaView refused the request (code 610)';
  assert.equal(translateStreetLevelError(http), http);
  assert.equal(translateStreetLevelError(refused), refused);
  for (const locale of ['es', 'ru']) {
    setLocale(locale);
    try {
      const shownHttp = translateStreetLevelError(http);
      const shownRefused = translateStreetLevelError(refused);
      assert.notEqual(shownHttp, http);
      assert.match(shownHttp, /503/);
      assert.notEqual(shownRefused, refused);
      assert.match(shownRefused, /610/);
    } finally {
      setLocale('en');
    }
  }
});

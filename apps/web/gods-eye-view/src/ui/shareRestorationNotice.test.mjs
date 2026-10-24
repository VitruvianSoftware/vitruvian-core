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

// Share-tracking restore notices are ready-made sentences per policy: a label
// dropped into a template cannot take the case (ru) or article (es) needed.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { setLocale } from '../i18n/index.js';
import { SHARE_TRACKING_RESTORE_POLICIES } from '../data/layerState.js';
import { shareTrackingRestoreNotice } from './shareRestoration.js';

const { flights, military, satellites } = SHARE_TRACKING_RESTORE_POLICIES;

test.afterEach(() => setLocale('en'));

test('en: the notices for every policy and outcome', () => {
  setLocale('en');
  const notice = (policy, classification) =>
    shareTrackingRestoreNotice({ ...policy, classification });
  assert.equal(notice(flights, 'expired'), 'Shared flight follow expired');
  assert.equal(
    notice(military, 'expired'),
    'Shared military flight follow expired',
  );
  assert.equal(
    notice(satellites, 'source-unavailable'),
    'Shared satellite could not be restored — feed unavailable',
  );
  assert.equal(
    notice(flights, 'source-unavailable'),
    'Shared flight could not be restored — feed unavailable',
  );
  assert.equal(
    notice(military, 'unavailable'),
    'Shared military flight is unavailable',
  );
  assert.equal(
    notice(satellites, 'unavailable'),
    'Shared satellite is unavailable',
  );
  // Unknown label and classification: the generic template still applies.
  assert.equal(
    shareTrackingRestoreNotice({ label: 'contact', classification: 'odd' }),
    'Shared contact is unavailable',
  );
  assert.equal(
    shareTrackingRestoreNotice({ classification: 'expired' }),
    'Shared entity follow expired',
  );
});

test('ru: the restore notices do not glue the nominative label into a genitive slot', () => {
  setLocale('ru');
  for (const policy of [flights, military, satellites]) {
    for (const classification of [
      'expired',
      'source-unavailable',
      'unavailable',
    ]) {
      const message = shareTrackingRestoreNotice({ ...policy, classification });
      // "Срок отслеживания" takes the genitive: рейса / спутника, never the
      // nominative label as stored in the policy.
      assert.doesNotMatch(
        message,
        /отслеживания (военный )?(рейс|спутник) /,
        message,
      );
      assert.doesNotMatch(message, /Shared|\{subject\}/, message);
    }
  }
});

test('es: the restore notices read with an article before the subject', () => {
  setLocale('es');
  const message = shareTrackingRestoreNotice({
    ...flights,
    classification: 'expired',
  });
  assert.doesNotMatch(message, /seguimiento de vuelo/, message);
  assert.doesNotMatch(message, /Shared/, message);
});

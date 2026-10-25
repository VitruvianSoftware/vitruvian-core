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

// The API-key cost tooltip states an incomplete estimate in the
// interface language; the tracker keeps its English note for diagnostics.
import test from 'node:test';
import assert from 'node:assert/strict';
import { setLocale } from '../i18n/index.js';
import { RealtimeCost } from './realtimeCost.js';
import { createVoiceCostTracker } from './voiceCost.js';

for (const locale of ['es', 'ru']) {
  test(`API-key cost tooltip for an incomplete session has no English (${locale})`, () => {
    setLocale(locale);
    try {
      const costTracker = createVoiceCostTracker({ tier: 'standard' });
      costTracker.markIncomplete();
      const host = {
        costTracker,
        voiceTier: 'standard',
        cloudVoiceAuth: 'api-key',
        sessionCloudVoiceAuth: 'api-key',
        isActive: () => false,
        ui: {
          costValue: { hidden: true, dataset: {}, title: '', textContent: '' },
        },
      };
      RealtimeCost.prototype.syncCostUi.call(host);
      const title = host.ui.costValue.title;
      assert.ok(title.length > 0);
      assert.doesNotMatch(
        title,
        /Estimate is incomplete|still in flight/,
        title,
      );
    } finally {
      setLocale('en');
    }
  });
}

test('API-key cost tooltip in English still ends with the tracker note', () => {
  const costTracker = createVoiceCostTracker({ tier: 'standard' });
  costTracker.markIncomplete();
  const host = {
    costTracker,
    voiceTier: 'standard',
    cloudVoiceAuth: 'api-key',
    sessionCloudVoiceAuth: 'api-key',
    isActive: () => false,
    ui: {
      costValue: { hidden: true, dataset: {}, title: '', textContent: '' },
    },
  };
  RealtimeCost.prototype.syncCostUi.call(host);
  assert.ok(host.ui.costValue.title.endsWith(` ${costTracker.state().note}`));
});

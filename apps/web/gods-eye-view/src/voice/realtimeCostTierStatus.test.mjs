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

// The status after a tier switch names the tier in the interface
// language, as the tier button does; the stored tier value stays English.
import test from 'node:test';
import assert from 'node:assert/strict';
import { setLocale, t } from '../i18n/index.js';
import { RealtimeCost } from './realtimeCost.js';

function harness() {
  const button = { textContent: '', title: '', setAttribute() {} };
  const ui = { tierButton: button, detail: {} };
  const statusCalls = [];
  const cost = new RealtimeCost({
    readUi: () => ui,
    readStatus: () => 'listening',
    operations: {
      isActive: () => true,
      isVoiceSessionSettled: () => false,
      setStatus: (status, detail) => statusCalls.push(detail),
    },
  });
  return { cost, button, statusCalls };
}

const EXPECTED = {
  en: {
    mini: 'MINI applies next session',
    standard: 'STANDARD applies next session',
  },
  ru: {
    mini: 'МИНИ — со следующей сессии',
    standard: 'СТАНДАРТ — со следующей сессии',
  },
  es: {
    mini: 'MINI desde la próxima sesión',
    standard: 'ESTÁNDAR desde la próxima sesión',
  },
};

for (const locale of Object.keys(EXPECTED)) {
  test(`${locale}: tier status names the tier in the interface language`, (ctx) => {
    setLocale(locale);
    ctx.after(() => setLocale('en'));
    for (const tier of ['mini', 'standard']) {
      const { cost, button, statusCalls } = harness();
      assert.equal(cost.setVoiceTier(tier), tier, 'stored tier stays English');
      assert.equal(statusCalls.at(-1), EXPECTED[locale][tier]);
      assert.equal(button.textContent, tier === 'mini' ? t('MINI') : t('STD'));
    }
  });
}

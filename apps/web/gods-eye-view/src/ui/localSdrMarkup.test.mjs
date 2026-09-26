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

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

import { expandApplicationHtml } from '../../build/application-html.js';
import { createBrowserViteConfig } from '../../build/vite.js';
import { R820T_GAIN_STEPS_DB } from '../sdr/gain.js';

const html = expandApplicationHtml(
  readFileSync(new URL('../../index.html', import.meta.url), 'utf8'),
);
const css = readFileSync(
  new URL('./styles/radio.css', import.meta.url),
  'utf8',
);

test('the Local RTL-SDR card lives inside the Radio panel with every control', () => {
  const radioStart = html.indexOf('id="radio-panel"');
  const cardStart = html.indexOf('id="sdr-radio-card"');
  const radioEnd = html.indexOf('</section>', radioStart);
  assert.ok(radioStart >= 0 && cardStart > radioStart && cardStart < radioEnd);
  for (const id of [
    'sdr-connection-state',
    'sdr-connect-btn',
    'sdr-locate-btn',
    'sdr-change-device-btn',
    'sdr-mode-fm-btn',
    'sdr-mode-adsb-btn',
    'sdr-gain-select',
    'sdr-adsb-stats',
    'sdr-stat-rate',
    'sdr-stat-heard',
    'sdr-stat-positioned',
    'sdr-stat-iq',
    'sdr-frequency-input',
    'sdr-tune-btn',
    'sdr-seek-back-btn',
    'sdr-seek-forward-btn',
    'sdr-volume',
    'sdr-status',
    'sdr-feed-status',
  ]) {
    assert.match(html, new RegExp(`id="${id}"`), `${id} is missing`);
  }
  assert.match(html, /id="sdr-status"[^>]*>Connect an RTL-SDR to begin\.</);
  assert.match(css, /\.sdr-radio-card\s*\{/);
});

test('the gain control offers AUTO plus every R820T step', () => {
  const start = html.indexOf('id="sdr-gain-select"');
  const select = html.slice(start, html.indexOf('</select>', start));
  const values = [...select.matchAll(/<option value="([^"]+)"/g)].map(
    (match) => match[1],
  );
  assert.deepEqual(values, [
    'auto',
    ...R820T_GAIN_STEPS_DB.map((step) => step.toFixed(1)),
  ]);
});

test('worker-reached SDR dependencies are pre-bundled and builds keep a separate cache', () => {
  const serve = createBrowserViteConfig();
  for (const dependency of [
    '@jtarrio/signals/demod/demodulator.js',
    '@jtarrio/signals/demod/modes.js',
    '@jtarrio/webrtlsdr/rtlsdr.js',
  ]) {
    assert.ok(serve.optimizeDeps.include.includes(dependency), dependency);
  }
  assert.equal(serve.cacheDir, undefined);
  assert.equal(
    createBrowserViteConfig({ command: 'build' }).cacheDir,
    'node_modules/.vite-build',
  );
});

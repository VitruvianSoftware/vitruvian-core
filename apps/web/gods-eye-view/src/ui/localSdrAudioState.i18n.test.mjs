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
import { localSdrCardView } from './localSdrPresentation.js';
import { setLocale } from '../i18n/index.js';

const fmStreaming = {
  webUsbSupported: true,
  connected: true,
  status: 'streaming',
  message: 'Streaming',
  mode: 'fm',
  frequencyHz: 98_500_000,
  volume: 0.8,
  gain: 'auto',
  seeking: false,
  seekMessage: '',
  decodedMessages: 0,
  messagesPerSecond: null,
  aircraftHeard: 0,
  aircraftPositioned: 0,
  deviceLabel: 'RTL2838',
  locationStatus: 'unknown',
  audioState: 'running',
  samplesPerSecond: 2_400_000,
  workerBlocks: 3,
  iqLevelDbfs: -20,
  audioLevelDbfs: -12,
};

test('FM status line names the AudioContext state in the UI language', () => {
  try {
    for (const [locale, state] of [
      ['es', 'running'],
      ['ru', 'running'],
      ['es', 'suspended'],
      ['ru', 'closed'],
      ['es', 'idle'],
      ['ru', 'idle'],
    ]) {
      setLocale(locale);
      const text = localSdrCardView({
        ...fmStreaming,
        audioState: state,
      }).statusText;
      assert.doesNotMatch(
        text,
        new RegExp(`audio[: ]+${state}\\b|аудио[: ]+${state}\\b`),
        `${locale}: ${text}`,
      );
    }
  } finally {
    setLocale('en');
  }
});

test('FM status line keeps the English AudioContext state words', () => {
  setLocale('en');
  for (const state of ['running', 'suspended', 'closed', 'idle']) {
    const text = localSdrCardView({
      ...fmStreaming,
      audioState: state,
    }).statusText;
    assert.ok(text.endsWith(` · audio ${state}`), text);
  }
});

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

// The CCTV summary line names the CAL badge, the source kind and the view
// band in the page language; unknown codes stay as uppercase codes.
import assert from 'node:assert/strict';
import test from 'node:test';
import { setLocale } from '../../i18n/index.js';
import {
  summaryCalLabel,
  summarySourceLabel,
  summaryViewBandLabel,
} from './presentation.js';

function inLocale(locale, run) {
  setLocale(locale);
  try {
    return run();
  } finally {
    setLocale('en');
  }
}

test('English keeps the summary codes', () => {
  assert.equal(summaryCalLabel('raw-prior'), 'RAW PRIOR');
  assert.equal(summarySourceLabel('image'), 'IMAGE');
  assert.equal(summarySourceLabel('hls'), 'HLS');
  assert.equal(summaryViewBandLabel('street'), 'STREET');
  assert.equal(summaryViewBandLabel('none'), 'NONE');
});

test('Portuguese summary values are translated', () => {
  inLocale('pt', () => {
    assert.equal(summaryCalLabel('raw-prior'), 'ESTIMATIVA BRUTA');
    assert.equal(summaryCalLabel('calibrated'), 'CALIBRADA');
    assert.equal(summarySourceLabel('IMAGE'), 'IMAGEM');
    assert.equal(summarySourceLabel('mjpeg'), 'MJPEG');
    assert.equal(summaryViewBandLabel('street'), 'RUA');
    assert.equal(summaryViewBandLabel('city'), 'CIDADE');
  });
});

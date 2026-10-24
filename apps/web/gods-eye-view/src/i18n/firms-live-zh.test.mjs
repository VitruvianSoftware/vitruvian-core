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
import { getLocale, setLocale } from './index.js';
import { createModel } from '../layers/firms/model.js';
import { createQueries } from '../layers/firms/queries.js';

const cases = [
  [0, '不到 1 分钟前', '<1m ago'],
  [120000, '2 分钟前', '2m ago'],
  [7200000, '2 小时前', '2h ago'],
];

for (const [age, zh, en] of cases) {
  test(`FIRMS live age ${age} ms has one relative-time suffix`, (context) => {
    const now = 1800000000000;
    context.mock.method(Date, 'now', () => now);
    const previousLocale = getLocale();
    const layerState = {
      _loading: false,
      _stale: false,
      _keyRequired: false,
      _error: null,
      _lastUpdate: now - age,
      _count: 1,
      _cellCount: 0,
      _fires: [],
    };
    const model = createModel({ services: { anchors: {} } });
    const { methods } = createQueries({
      layerState,
      components: { model },
      config: {},
    });
    try {
      setLocale('en');
      assert.equal(methods.getStats().loadingLabel, `LIVE · updated ${en}`);
      setLocale('zh-CN');
      assert.equal(methods.getStats().loadingLabel, `实时 · 更新于 ${zh}`);
    } finally {
      setLocale(previousLocale);
    }
  });
}

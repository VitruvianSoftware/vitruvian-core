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
import { normalizeRegionalArticles } from './regionalModel.js';
test('compact source dates must denote an actual calendar instant', () => {
  for (const date of [
    '20260230T120000Z',
    '20260431T120000Z',
    '20261301T120000Z',
    '20260716T240000Z',
    '20260716T126000Z',
    '20260716T120060Z',
  ]) {
    const [article] = normalizeRegionalArticles({
      articles: [
        {
          title: 'Fixture',
          url: 'https://fixture.example/news',
          seendate: date,
        },
      ],
    });
    assert.equal(article.publishedAt, null, date);
    assert.equal(article.title, 'Fixture');
  }
  for (const [input, expected] of [
    ['20240229T004500Z', '2024-02-29T00:45:00Z'],
    ['20260716T000000Z', '2026-07-16T00:00:00Z'],
    ['2026-07-16T12:00:00Z', '2026-07-16T12:00:00.000Z'],
  ]) {
    assert.equal(
      normalizeRegionalArticles({
        articles: [
          {
            title: 'Fixture',
            url: 'https://fixture.example/news',
            seendate: input,
          },
        ],
      })[0].publishedAt,
      expected,
    );
  }
});

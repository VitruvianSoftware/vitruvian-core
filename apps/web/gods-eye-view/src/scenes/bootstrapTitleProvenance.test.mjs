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
import { SCENE_RECIPES, displayShotTitle } from './recipes.js';
import { setLocale } from '../i18n/index.js';

test('an operator-typed title in the built-in Nepal scene stays as typed', () => {
  const scene = SCENE_RECIPES.find((r) => r.id === 'bhote-koshi-nepal-scene');
  assert.ok(scene, 'built-in bootstrap scene exists');
  for (const locale of ['ru', 'es', 'it', 'zh-CN', 'zh-Hant']) {
    setLocale(locale);
    const title = 'Global Incident Context';
    // A shot captured by the operator: no sourcePackId, renamed to this title.
    const shown = displayShotTitle(
      title,
      { id: 'shot-user', title },
      { id: scene.id },
    );
    assert.equal(shown, title, `${locale}: got ${shown}`);
  }
});

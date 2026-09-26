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

import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';

const read = (path) => readFileSync(new URL(path, import.meta.url), 'utf8');

// The rail's measuring pass lifts these panel scrollers to their natural
// height, which clamps their scroll offset to zero. Only scrollers tagged
// `data-rail-scroller` get their offset restored afterwards, so every lifted
// scroller must carry the tag or a layout pass snaps it back to the top.
test('every scroller the rail measuring pass lifts restores its scroll offset', () => {
  const css = read('./styles/layers.css');
  const templates = [
    read('./templates/context.html'),
    read('./templates/layer-panels.html'),
  ].join('\n');
  const lifted = [
    ...css.matchAll(
      /#right-context-rail\[data-rail-measuring\]\s*>\s*\[data-panel-id\]:not\(\.collapsed\)\s*>\s*\.([a-z-]+)/g,
    ),
  ].map((match) => match[1]);
  assert.ok(lifted.length > 0, 'measuring CSS lists lifted scrollers');
  for (const className of lifted) {
    const tag = templates.match(
      new RegExp(`<div class="${className}"[^>]*>`),
    )?.[0];
    if (!tag) continue;
    assert.match(tag, /data-rail-scroller/, `${className} restores its scroll`);
  }
});

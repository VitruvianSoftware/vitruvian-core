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
import { syncRadioPanelPlacement } from './radioPanelPlacement.js';

function node() {
  return {
    children: [],
    selectors: {},
    parentElement: null,
    moves: 0,
    querySelector(selector) {
      return this.selectors[selector] || null;
    },
    append(child) {
      this.insertBefore(child, null);
    },
    insertBefore(child, before) {
      if (child.parentElement) {
        const siblings = child.parentElement.children;
        siblings.splice(siblings.indexOf(child), 1);
      }
      const index = before
        ? this.children.indexOf(before)
        : this.children.length;
      this.children.splice(index, 0, child);
      child.parentElement = this;
      child.moves++;
    },
  };
}

test('all themes keep the same Radio controls nested in Context', () => {
  const panel = node(),
    context = node(),
    rail = node(),
    inner = node(),
    body = node();
  context.selectors['.global-context-panel-inner'] = inner;
  context.selectors['.cyber-panel-body'] = body;
  inner.append(panel);
  const nodes = {
    'radio-panel': panel,
    'global-context-panel': context,
    'right-context-rail': rail,
  };
  const doc = {
    documentElement: { dataset: {} },
    getElementById: (id) => nodes[id],
  };
  for (let cycle = 0; cycle < 3; cycle++) {
    doc.documentElement.dataset.uiTheme = 'cyber';
    syncRadioPanelPlacement(doc);
    assert.equal(panel.parentElement, body);
    const moves = panel.moves;
    syncRadioPanelPlacement(doc);
    assert.equal(panel.moves, moves, 'no mutation feedback loop');
    delete doc.documentElement.dataset.uiTheme;
    syncRadioPanelPlacement(doc);
    assert.equal(panel.parentElement, body);
  }
  // Recover a hierarchy left by the previous Cyber implementation without
  // recreating the player, changing playback, or mutating collapse state.
  rail.append(panel);
  doc.documentElement.dataset.uiTheme = 'cyber';
  syncRadioPanelPlacement(doc);
  assert.equal(panel.parentElement, body);
});

test('placement is inert before the complete shell exists', () => {
  assert.doesNotThrow(() => syncRadioPanelPlacement(null));
  assert.doesNotThrow(() =>
    syncRadioPanelPlacement({
      documentElement: { dataset: { uiTheme: 'cyber' } },
      getElementById: () => null,
    }),
  );
});

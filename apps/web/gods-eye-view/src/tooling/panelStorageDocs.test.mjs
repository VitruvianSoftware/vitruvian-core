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
import { readFile } from 'node:fs/promises';
import path from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';

const root = fileURLToPath(new URL('../..', import.meta.url));

// Documentation consistency only: that every storage key a document spells out
// is the key the code writes. Whether deleting one has the effect the document
// claims is not checked here.
const DOCUMENTED_KEYS = [
  ['docs/KNOWN-ISSUES.md', 'godsEyeView.{layout}.panelCollapsed.cctv-panel'],
  ['docs/KNOWN-ISSUES.md', 'godsEyeView.{layout}.panelCollapsed.<panel-id>'],
  ['docs/KNOWN-ISSUES.md', 'godsEyeView.{position}.panelPos.<panel-id>'],
  ['scripts/dev-fresh.sh', 'godsEyeView.{layout}.panelCollapsed.cctv-panel'],
  ['docs/CURRENT-STATE.md', 'godsEyeView.{position}.panelPos.<panel-id>'],
  ['docs/CURRENT-STATE.md', 'godsEyeView.{position}.panelPos.<id>'],
  ['docs/CURRENT-STATE.md', 'godsEyeView.{layout}.panelCollapsed.<panel-id>'],
];

test('documented panel storage keys are the keys the code writes', async () => {
  const source = await readFile(
    path.join(root, 'src/ui/panelPositionControls.js'),
    'utf8',
  );
  const version = (name) => {
    const [, found] =
      source.match(new RegExp(`const ${name} = '([^']+)';`)) || [];
    assert.ok(found, `panelPositionControls.js must declare ${name}`);
    return found;
  };
  const position = version('PANEL_POSITION_STORAGE_VERSION');
  const layout = version('PANEL_LAYOUT_STORAGE_VERSION');

  const seen = new Map();
  for (const [file, shape] of DOCUMENTED_KEYS) {
    if (!seen.has(file))
      seen.set(file, await readFile(path.join(root, file), 'utf8'));
    const expected = shape
      .replace('{position}', position)
      .replace('{layout}', layout);
    assert.ok(
      seen.get(file).includes(expected),
      `${file} must use ${expected}`,
    );
  }

  // A document that still names a superseded version sends the reader to a key
  // nothing writes.
  for (const [file, content] of seen) {
    const stalePositions = [
      ...content.matchAll(/godsEyeView\.(v\d+)\.panelPos/g),
    ]
      .map(([, found]) => found)
      .filter((found) => found !== position);
    assert.deepEqual(
      stalePositions,
      [],
      `${file} names superseded position keys`,
    );
    const staleCollapsed = [
      ...content.matchAll(/godsEyeView\.(v\d+)\.panelCollapsed/g),
    ]
      .map(([, found]) => found)
      .filter((found) => found !== layout);
    assert.deepEqual(
      staleCollapsed,
      [],
      `${file} names superseded collapsed-state keys`,
    );
  }
});

test('the documented outcomes hold: default, stored open, stored shut, and a shared view', async () => {
  // The instructions promise two different outcomes; both are exercised here
  // against the code that decides them.
  const { PanelPositionControls } =
    await import('../ui/panelPositionControls.js');
  const html = await readFile(
    path.join(root, 'src/ui/templates/layer-panels.html'),
    'utf8',
  );
  assert.match(
    html,
    /<div id="cctv-panel" class="panel-collapsible collapsed"/,
    'the CCTV panel starts collapsed in the markup',
  );

  const saved = {
    document: globalThis.document,
    localStorage: globalThis.localStorage,
  };
  const classes = new Set(['panel-collapsible', 'collapsed']);
  const panel = {
    classList: {
      contains: (name) => classes.has(name),
      toggle: (name, active) =>
        active ? classes.add(name) : classes.delete(name),
      add: (name) => classes.add(name),
      remove: (name) => classes.delete(name),
    },
  };
  const store = new Map();
  globalThis.document = { getElementById: () => panel };
  globalThis.localStorage = {
    getItem: (key) => (store.has(key) ? store.get(key) : null),
    setItem: (key, value) => store.set(key, String(value)),
    removeItem: (key) => store.delete(key),
  };
  try {
    const controls = new PanelPositionControls({
      syncPanelCollapseButton: () => {},
      layoutRightPanels: () => {},
      syncCctvPanelViewport: () => {},
      showToast: () => {},
    });

    // Nothing stored: the markup default wins, and the panel is collapsed. So
    // deleting the key is a reset, not a way to open the panel.
    controls._restorePanelCollapsedState('cctv-panel');
    assert.equal(classes.has('collapsed'), true);

    // The value the documents tell a reader to set.
    store.set('godsEyeView.v6.panelCollapsed.cctv-panel', '0');
    controls._restorePanelCollapsedState('cctv-panel');
    assert.equal(classes.has('collapsed'), false);

    // ...and the opposite value keeps it shut, so '0' is doing the work.
    store.set('godsEyeView.v6.panelCollapsed.cctv-panel', '1');
    controls._restorePanelCollapsedState('cctv-panel');
    assert.equal(classes.has('collapsed'), true);

    // A view opened from a share link is laid out from the link: the shell
    // restores with allowStored false, and the stored value is not consulted.
    // This is why the console workaround is documented for ordinary loads only.
    store.set('godsEyeView.v6.panelCollapsed.cctv-panel', '0');
    controls._restorePanelCollapsedState('cctv-panel', { allowStored: false });
    assert.equal(
      classes.has('collapsed'),
      true,
      'a shared view must ignore the stored open state',
    );
  } finally {
    globalThis.document = saved.document;
    globalThis.localStorage = saved.localStorage;
  }
});

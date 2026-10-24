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
import test from 'node:test';

import { PanelChrome } from './panelChrome.js';
import { PanelLayoutController } from './panelLayoutController.js';

function classList(initial = []) {
  const values = new Set(initial);
  return {
    contains: (value) => values.has(value),
    add: (...items) => items.forEach((item) => values.add(item)),
    remove: (...items) => items.forEach((item) => values.delete(item)),
    toggle(value, force) {
      if (force === true) values.add(value);
      else if (force === false) values.delete(value);
      else if (values.has(value)) values.delete(value);
      else values.add(value);
      return values.has(value);
    },
  };
}

test('opening an already-open Context still closes a stale compact Radio disclosure', (t) => {
  const priorDocument = globalThis.document;
  const contextPanel = {
    id: 'global-context-panel',
    classList: classList(),
  };
  globalThis.document = {
    documentElement: { dataset: { uiTheme: 'tactical' } },
    getElementById(id) {
      return id === 'global-context-panel' ? contextPanel : null;
    },
  };
  t.after(() => {
    globalThis.document = priorDocument;
  });

  const radioDock = { classList: classList(['disclosure-open']) };
  const calls = [];
  const owner = {
    _contextRadioDock: radioDock,
    _setRadioDisclosure(open) {
      calls.push(open);
      radioDock.classList.toggle('disclosure-open', open);
    },
    _leftPanelStack: null,
    _rightPanelStack: null,
    _panelLayout: {
      _leftStackPreferredPanelId: null,
      _rightStackPreferredPanelId: null,
    },
    _syncPanelCollapseButton() {},
    _scheduleLeftPanelLayout() {},
    _scheduleRightPanelLayout() {},
    shareLinkManager: null,
    cockpitView: null,
  };

  PanelChrome.prototype.setPanelCollapsed.call(
    owner,
    'global-context-panel',
    false,
  );

  assert.deepEqual(calls, [false]);
  assert.equal(radioDock.classList.contains('disclosure-open'), false);
});

test('adaptive rail restore hides compact Radio before revealing Context', (t) => {
  const priorRaf = globalThis.requestAnimationFrame;
  let nextFrame;
  globalThis.requestAnimationFrame = (callback) => {
    nextFrame = callback;
    return 1;
  };
  t.after(() => {
    globalThis.requestAnimationFrame = priorRaf;
  });

  // Valid starting state: the tactical rail automatically collapsed Context,
  // and the user opened the compact Radio controls from its header.
  const contextPanel = {
    id: 'global-context-panel',
    classList: classList(['collapsed', 'layout-auto-collapsed']),
  };
  const radioDock = { classList: classList(['disclosure-open']) };
  const radioMini = { hidden: false };
  const calls = [];
  const chrome = {
    _contextRadioDock: radioDock,
    _setRadioDisclosure(open) {
      calls.push(`disclosure:${open}`);
      radioDock.classList.toggle('disclosure-open', open);
      radioMini.hidden = !open;
    },
    _syncPanelCollapseButton(panel) {
      calls.push(`button:${panel.id}`);
    },
  };
  const layout = {
    destroyed: false,
    _rightStackLayoutFrame: null,
    _rightStackReconsiderAutoCollapse: false,
    _rightPanelStack: {
      querySelectorAll: (selector) =>
        selector === '.layout-auto-collapsed' ? [contextPanel] : [],
    },
    _syncPanelCollapseButton(panel) {
      PanelChrome.prototype._syncRailPanelCollapseButton.call(chrome, panel);
    },
    _syncRightPanelAdaptiveLayout() {
      calls.push('layout');
    },
  };

  PanelLayoutController.prototype._scheduleRightPanelLayout.call(layout, {
    reconsiderAutoCollapse: true,
  });
  assert.equal(contextPanel.classList.contains('collapsed'), true);
  assert.equal(radioMini.hidden, false);
  nextFrame();

  assert.equal(contextPanel.classList.contains('collapsed'), false);
  assert.equal(contextPanel.classList.contains('layout-auto-collapsed'), false);
  assert.equal(radioDock.classList.contains('disclosure-open'), false);
  assert.equal(radioMini.hidden, true);
  assert.deepEqual(calls, [
    'disclosure:false',
    'button:global-context-panel',
    'layout',
  ]);
});

test('real PanelChrome constructor wires rail restore to compact Radio owner', (t) => {
  const priorDocument = globalThis.document;
  const priorRaf = globalThis.requestAnimationFrame;
  let nextFrame;
  const contextPanel = {
    id: 'global-context-panel',
    classList: classList(['collapsed', 'layout-auto-collapsed']),
  };
  const rightRail = {
    querySelectorAll(selector) {
      return selector === '.layout-auto-collapsed' ? [contextPanel] : [];
    },
  };
  globalThis.document = {
    getElementById(id) {
      return id === 'right-context-rail' ? rightRail : null;
    },
  };
  globalThis.requestAnimationFrame = (callback) => {
    nextFrame = callback;
    return 1;
  };
  t.after(() => {
    globalThis.document = priorDocument;
    globalThis.requestAnimationFrame = priorRaf;
  });

  const dock = { classList: classList(['disclosure-open']) };
  const calls = [];
  const chrome = new PanelChrome({
    elements: { _contextRadioDock: dock },
    operations: {
      _setRadioDisclosure(open) {
        calls.push(`disclosure:${open}`);
        dock.classList.toggle('disclosure-open', open);
      },
      _syncPanelCollapseButton(panel) {
        calls.push(`button:${panel.id}`);
      },
    },
    readHud: () => ({ visible: true, getVariant: () => 'tactical' }),
    readCockpit: () => null,
    readShareLinks: () => null,
    readInitialShare: () => null,
    readScrollRestoreOwner: () => null,
    readDisplayScrollTop: () => 0,
  });
  chrome._panelLayout._syncRightPanelAdaptiveLayout = () => {
    calls.push('layout');
  };

  chrome._panelLayout._scheduleRightPanelLayout({
    reconsiderAutoCollapse: true,
  });
  assert.equal(typeof nextFrame, 'function');
  assert.equal(dock.classList.contains('disclosure-open'), true);
  nextFrame();

  assert.equal(contextPanel.classList.contains('collapsed'), false);
  assert.equal(dock.classList.contains('disclosure-open'), false);
  assert.deepEqual(calls, [
    'disclosure:false',
    'button:global-context-panel',
    'layout',
  ]);
});

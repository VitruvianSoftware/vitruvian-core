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

// The HUD's 250 ms telemetry readout skips ticks in a hidden page, except in
// an inline panel, whose host may report it hidden while it is on screen.
//
// hud.js imports `mgrs`, which Node's ESM loader cannot read named exports
// from, so a module hook swaps it for a stub before the import (the same
// setup as hudAltitudeDatum.test.mjs).
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { hudReadouts } from './testSupport/hudReadouts.mjs';
import { registerHooks } from 'node:module';

const MGRS_STUB_URL = 'gev-test-stub:mgrs';
registerHooks({
  resolve(specifier, context, next) {
    if (specifier === 'mgrs') return { url: MGRS_STUB_URL, shortCircuit: true };
    return next(specifier, context);
  },
  load(url, context, next) {
    if (url === MGRS_STUB_URL) {
      return {
        format: 'module',
        shortCircuit: true,
        source: 'export function forward() { return "10SEG55776339"; }\nexport default { forward };\n',
      };
    }
    return next(url, context);
  },
});

const { IntelHUD } = await import('./hud.js');

function installHiddenPage() {
  const { elements, publish } = hudReadouts();
  const previousDocument = globalThis.document;
  globalThis.document = {
    hidden: true,
    visibilityState: 'hidden',
    getElementById: (id) => elements.get(id) ?? null,
    querySelectorAll: () => [],
    addEventListener() {},
    removeEventListener() {},
  };
  const viewer = {
    camera: {
      pitch: -Math.PI / 2,
      positionCartographic: { latitude: 0.7, longitude: -1.2, height: 500 },
      computeViewRectangle: () => undefined,
      moveStart: { addEventListener() {}, removeEventListener() {} },
      moveEnd: { addEventListener() {}, removeEventListener() {} },
    },
  };
  return {
    alt: () => elements.get('hud-alt').textContent,
    viewer,
    publish,
    restore() {
      if (previousDocument === undefined) delete globalThis.document;
      else globalThis.document = previousDocument;
    },
  };
}

test('the HUD readout pauses in a hidden page but keeps updating in an inline panel', (t) => {
  t.mock.timers.enable({ apis: ['setInterval'] });
  const page = installHiddenPage();
  let hud;
  try {
    hud = new IntelHUD(page.viewer, { publish: page.publish });
    hud._visible = true;

    t.mock.timers.tick(250);
    assert.equal(
      page.alt(),
      'ALT: --m   SUN: --° EL',
      'a hidden page skips the telemetry tick',
    );

    globalThis.GEV_EMBED_INLINE = true;
    t.mock.timers.tick(250);
    assert.match(
      page.alt(),
      /^ALT: 500m/,
      'an inline panel reported hidden keeps its readout updating',
    );
  } finally {
    delete globalThis.GEV_EMBED_INLINE;
    hud?.destroy();
    page.restore();
  }
});

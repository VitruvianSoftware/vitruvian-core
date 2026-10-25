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

import { setLocale } from '../i18n/index.js';
import { SdrController } from '../sdr/controller.js';
import { LocalSdrControls } from './localSdrControls.js';
import { localSdrCardView } from './localSdrPresentation.js';

function stubDocument() {
  const elements = new Map();
  const doc = {
    activeElement: null,
    getElementById(id) {
      if (!elements.has(id)) {
        const listeners = new Map();
        elements.set(id, {
          id,
          value: '',
          hidden: false,
          disabled: false,
          textContent: '',
          ownerDocument: doc,
          classList: { toggle() {} },
          setAttribute() {},
          closest: () => null,
          addEventListener(type, handler) {
            listeners.set(type, handler);
          },
        });
      }
      return elements.get(id);
    },
  };
  return doc;
}

function stubRadio() {
  const listeners = new Set();
  return {
    subscribe(fn) {
      listeners.add(fn);
      return () => listeners.delete(fn);
    },
    stopPlayback() {},
    emit(state) {
      for (const fn of listeners) fn(state);
    },
  };
}

async function stopLocalFmForInternetRadio(t, locale) {
  setLocale(locale);
  const receiver = new SdrController({ webUsb: {}, storage: null });
  // Pretend local FM is streaming (no real device: stop() has nothing to tear down).
  receiver._setState({ connected: true, status: 'streaming', mode: 'fm' });
  const radio = stubRadio();
  const controls = new LocalSdrControls({
    document: stubDocument(),
    receiver,
    radio,
  });
  t.after(() => {
    controls.destroy();
    setLocale('en');
  });

  radio.emit({ audioState: 'playing' });
  await new Promise((resolve) => setTimeout(resolve, 50));
  assert.equal(receiver.state.connected, false);
  return localSdrCardView(receiver.state);
}

for (const locale of ['es', 'ru']) {
  test(`FM stop message after internet radio start is shown in ${locale}`, async (t) => {
    const view = await stopLocalFmForInternetRadio(t, locale);
    assert.notEqual(
      view.connectLabel,
      'CONNECT',
      'surrounding UI is translated',
    );
    assert.notEqual(
      view.statusText,
      'Local FM stopped: internet radio started',
      `status must not be the English literal under ${locale}`,
    );
  });
}

test('FM stop message after internet radio start stays English', async (t) => {
  const view = await stopLocalFmForInternetRadio(t, 'en');
  assert.equal(view.statusText, 'Local FM stopped: internet radio started');
});

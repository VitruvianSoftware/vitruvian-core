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

// src/ui/rail/fieldValue.test.mjs — v-field-value never writes over a field
// that has focus, and leaves a field alone for a null value.
import '../../testSupport/registerDom.mjs';
import test from 'node:test';
import assert from 'node:assert/strict';
import { createApp, h, nextTick, shallowRef, withDirectives } from 'vue';
import { vFieldValue } from './fieldValue.js';

test('a render writes the value unless the field has focus or the value is null', async (t) => {
  document.body.replaceChildren();
  const host = document.body.appendChild(document.createElement('div'));
  const value = shallowRef('98.5');
  const app = createApp({
    render: () =>
      withDirectives(h('input', { type: 'number', id: 'field' }), [
        [vFieldValue, value.value],
      ]),
  });
  app.mount(host);
  t.after(() => app.unmount());
  const field = document.getElementById('field');
  assert.equal(field.value, '98.5');
  field.focus();
  field.value = '101.1';
  value.value = '98.7';
  await nextTick();
  assert.equal(field.value, '101.1', 'typing stands');
  field.blur();
  value.value = null;
  await nextTick();
  assert.equal(field.value, '101.1', 'null leaves it');
  value.value = '98.9';
  await nextTick();
  assert.equal(field.value, '98.9');
});

test('a render that disables a focused field leaves its value', async (t) => {
  document.body.replaceChildren();
  const host = document.body.appendChild(document.createElement('div'));
  const state = shallowRef({ value: 'auto', disabled: false });
  const app = createApp({
    render: () =>
      withDirectives(
        h('select', { id: 'gain', disabled: state.value.disabled }, [
          h('option', { value: 'auto' }, 'AUTO'),
          h('option', { value: '20.7' }, '20.7 dB'),
        ]),
        [[vFieldValue, state.value.value]],
      ),
  });
  app.mount(host);
  t.after(() => app.unmount());
  const gain = document.getElementById('gain');
  // Browsers drop focus from a field that becomes disabled; happy-dom does
  // not, so focus moves to the page here.
  const page = document.body.appendChild(document.createElement('button'));
  const drop = () => page.focus();
  const disabled = Object.getOwnPropertyDescriptor(
    Object.getPrototypeOf(gain),
    'disabled',
  );
  Object.defineProperty(gain, 'disabled', {
    get: () => disabled.get.call(gain),
    set: (on) => {
      disabled.set.call(gain, on);
      if (on) drop();
    },
  });
  const setAttribute = gain.setAttribute.bind(gain);
  gain.setAttribute = (name, value) => {
    setAttribute(name, value);
    if (name === 'disabled') drop();
  };
  gain.focus();
  gain.value = '20.7';
  state.value = { value: 'auto', disabled: true };
  await nextTick();
  assert.equal(gain.disabled, true);
  assert.equal(document.activeElement === gain, false, 'focus left the field');
  assert.equal(gain.value, '20.7');
});

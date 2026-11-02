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

import { after, before, test } from 'node:test';
import assert from 'node:assert/strict';
import { installVueDom } from '../../testSupport/vueDom.mjs';

let mount;
let UiBadge;
let UiEmpty;
let uninstall;
before(async () => {
  uninstall = installVueDom();
  ({ mount } = await import('@vue/test-utils'));
  UiBadge = (await import('./UiBadge.vue')).default;
  UiEmpty = (await import('./UiEmpty.vue')).default;
});
after(() => uninstall());

test('a badge carries the kit classes, Core’s and the caller’s', async () => {
  const wrapper = mount(UiBadge, {
    attrs: { id: 'cal', class: 'gev-status-badge--box', role: 'status' },
    slots: { default: 'CAL · --' },
  });
  const badge = wrapper.get('span');
  assert.deepEqual(badge.classes(), [
    'ui-badge',
    'gev-status-badge',
    'ui-badge--neutral',
    'gev-status-badge--box',
  ]);
  assert.equal(badge.attributes('role'), 'status');
  assert.equal(badge.element.textContent, 'CAL · --');
  await wrapper.setProps({ tone: 'warn' });
  assert.ok(badge.classes().includes('ui-badge--warn'));
  wrapper.unmount();
});

test('an empty state is its title, then its hint', async () => {
  const wrapper = mount(UiEmpty, {
    props: { title: 'No shots yet.' },
    attrs: { class: 'scene-shot-empty', hidden: true },
  });
  const empty = wrapper.get('div');
  assert.deepEqual(empty.classes(), ['ui-empty', 'scene-shot-empty']);
  assert.equal(empty.element.textContent, 'No shots yet.');
  assert.equal(empty.attributes('title'), undefined);
  assert.equal(empty.element.hidden, true);
  await wrapper.setProps({ hint: 'Capture one.' });
  assert.equal(empty.get('.ui-empty__hint').text(), 'Capture one.');
  wrapper.unmount();
});

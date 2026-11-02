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

// src/ui/views/mountApplicationViews.test.mjs — a page's view hosts render
// their views, and an application can leave views out, over happy-dom.
import '../../testSupport/registerDom.mjs';
import test from 'node:test';
import assert from 'node:assert/strict';
import { createApplication } from '../../app/application.js';
import { mountApplicationViews } from './index.js';

function page(names) {
  document.body.replaceChildren();
  for (const name of names) {
    const host = document.createElement('div');
    host.className = 'gev-view';
    host.setAttribute('data-gev-view', name);
    document.body.append(host);
  }
}

const hostNames = () =>
  [...document.querySelectorAll('[data-gev-view]')].map((host) =>
    host.getAttribute('data-gev-view'),
  );

test('omitted views lose their hosts and the rest render', () => {
  page(['welcome', 'provider-settings']);
  mountApplicationViews(document, { omit: ['provider-settings'] });
  assert.deepEqual(hostNames(), ['welcome']);
  assert.equal(document.getElementById('key-setup-chip'), null);
  assert.ok(
    document.querySelector('[data-gev-view="welcome"]').children.length,
  );
});

test('a view an earlier call rendered is unmounted when a later call omits it', () => {
  page(['welcome', 'provider-settings']);
  mountApplicationViews(document);
  assert.ok(document.getElementById('key-setup-chip'));
  mountApplicationViews(document, { omit: ['provider-settings'] });
  assert.deepEqual(hostNames(), ['welcome']);
  assert.equal(document.getElementById('key-setup-chip'), null);
});

test('unknown view names are refused, in the page or in the omit list', () => {
  page([]);
  for (const name of ['toString', 'constructor'])
    assert.throws(
      () => mountApplicationViews(document, { omit: [name] }),
      /Unknown application view/,
    );
  page(['toString']);
  assert.throws(
    () => mountApplicationViews(document),
    /Unknown application view/,
  );
  assert.throws(
    () => mountApplicationViews(document, { omit: ['nope'] }),
    /Unknown application view: nope/,
  );
  page(['nope']);
  assert.throws(
    () => mountApplicationViews(document),
    /Unknown application view: nope/,
  );
});

test('createApplication leaves out the views its omitViews names', () => {
  page(['welcome', 'provider-settings']);
  const noop = () => ({});
  createApplication({
    createScene: noop,
    createControls: noop,
    createData: noop,
    createTools: noop,
    omitViews: ['provider-settings'],
  });
  assert.deepEqual(hostNames(), ['welcome']);
});

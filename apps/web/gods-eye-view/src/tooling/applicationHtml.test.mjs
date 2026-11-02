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
import { readFileSync } from 'node:fs';
import { APPLICATION_VIEWS } from '../ui/views/index.js';
import { readApplicationHtml } from '../testSupport/applicationHtml.mjs';

const source = readFileSync(new URL('../../index.html', import.meta.url), 'utf8');

test('the standalone document hosts every view once and keeps element ids unique', async () => {
  const hosts = [...source.matchAll(/data-gev-view="([^"]+)"/g)].map((match) => match[1]);
  // Order is stacking order for fixed elements that share a z-index.
  assert.deepEqual(hosts, ['scene-chrome', 'cockpit', 'display-controls', 'command-dock', 'layer-panels', 'context', 'welcome', 'provider-settings', 'intel-hud']);
  assert.deepEqual([...hosts].sort(), Object.keys(APPLICATION_VIEWS).sort());
  const html = await readApplicationHtml();
  const ids = [...html.matchAll(/\sid="([^"]+)"/g)].map((match) => match[1]);
  assert.equal(new Set(ids).size, ids.length);
  assert.match(html, /id="cesiumContainer"/);
  assert.match(html, /type="module" src="\/src\/main.js"/);
});

test('the loading screen is static markup, so it paints before any script runs', () => {
  const loading = source.indexOf('id="loading-screen"');
  assert.ok(loading > 0);
  assert.ok(loading < source.indexOf('type="module" src="/src/main.js"'));
  assert.match(source, /class="loader-status" data-i18n>Initializing photorealistic world\.\.\.</);
  assert.doesNotMatch(source, /gev:template/);
});

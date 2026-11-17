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
import { panelRuntime } from './globePanelRuntime.js';

const element = () => ({
  isConnected: true,
  hidden: true,
  textContent: '',
  addEventListener() {},
  remove() {
    this.isConnected = false;
  },
});

test('every view the panel posts says whether its result was issued just now', async () => {
  const savedWindow = globalThis.window;
  const savedDocument = globalThis.document;
  const views = [];
  const parent = { postMessage() {} };
  const windowRef = new EventTarget();
  Object.assign(windowRef, {
    parent,
    postMessage: (message) => {
      if (message?.type === 'gev:view') views.push(message);
    },
  });
  const elements = { status: element(), open: element(), expand: element() };
  globalThis.window = windowRef;
  globalThis.document = {
    getElementById: (id) => elements[id] ?? null,
    addEventListener() {},
    baseURI: 'https://host.example/panel',
    body: { clientWidth: 600 },
  };
  const deliver = (source, data) => {
    const event = new Event('message');
    Object.assign(event, { source, data });
    windowRef.dispatchEvent(event);
  };
  const result = (issuedAt) => ({
    jsonrpc: '2.0',
    method: 'ui/notifications/tool-result',
    params: {
      structuredContent: {
        url: 'http://localhost:4173/#sl=google,48.85840,2.29450',
        issued_at: issuedAt,
        view: { camera: { lat: 48.8584, lon: 2.2945 } },
      },
    },
  });
  try {
    panelRuntime({
      appBaseUrl: 'http://localhost:4173/',
      panelBase: '/panel/',
      protocolVersion: '2025-06-18',
      panelHeight: 480,
    });
    deliver(windowRef, { type: 'gev:ready' });
    deliver(parent, result(Date.now()));
    // A host replaying an old result on the same mount.
    deliver(parent, result(Date.now() - 60 * 60 * 1000));
    deliver(parent, result(undefined));
  } finally {
    globalThis.window = savedWindow;
    globalThis.document = savedDocument;
  }
  assert.deepEqual(
    views.map((message) => message.fresh),
    [true, false, false],
  );
});

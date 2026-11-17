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

// Errors thrown in the render loop outside Scene's tryAndCatchError. Drives
// Cesium's real startRenderLoop through the useDefaultRenderLoop setter.
import test from 'node:test';
import assert from 'node:assert/strict';
import * as Cesium from 'cesium';
import { renderLoopFixture } from './renderLoopFixture.mjs';

function runLoop(render) {
  const scene = {
    renderError: new Cesium.Event(),
    preUpdate: new Cesium.Event(),
    postRender: new Cesium.Event(),
    requestRender() {},
    initializeFrame() {},
    render,
  };
  const fixture = renderLoopFixture(scene);
  fixture.viewer.useDefaultRenderLoop = true;
  fixture.runFrames(3);
  return { ...fixture, uninstall: fixture.restore };
}

test('an error thrown outside tryAndCatchError still shows the notice', () => {
  // Scene.render raises preRender outside tryAndCatchError (Scene.js:4439),
  // so a listener's exception propagates.
  const { widget, store, logged, uninstall } = runLoop(function () {
    this.preUpdate.raiseEvent(this);
    throw new TypeError("Cannot read properties of undefined (reading 'x')");
  });
  assert.equal(widget.useDefaultRenderLoop, false);
  assert.equal(store.renderFailure?.reason, 'render-error');
  assert.equal(logged.length, 1);
  uninstall();
});

test('an error Scene raised and threw on with rethrowRenderErrors is reported once', () => {
  const { store, logged, uninstall } = runLoop(function () {
    this.preUpdate.raiseEvent(this);
    const error = new Error('boom');
    this.renderError.raiseEvent(this, error);
    throw error;
  });
  assert.equal(store.renderFailure?.detail, 'boom');
  assert.equal(logged.length, 1);
  uninstall();
});

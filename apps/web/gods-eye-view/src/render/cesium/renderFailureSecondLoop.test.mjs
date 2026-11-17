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

// Retry after an error Scene catches itself: the loop is marked stopped but
// its next frame is still queued, so an early Retry must not start a second
// loop. Drives Cesium's real startRenderLoop and useDefaultRenderLoop setter.
import test from 'node:test';
import assert from 'node:assert/strict';
import * as Cesium from 'cesium';
import { renderLoopFixture } from './renderLoopFixture.mjs';

function setup({ targetFrameRate } = {}) {
  const scene = {
    renderError: new Cesium.Event(),
    preUpdate: new Cesium.Event(),
    preRender: new Cesium.Event(),
    postRender: new Cesium.Event(),
    broken: false,
    drawn: 0,
    requestRender() {},
    initializeFrame() {},
    // Scene.render (Scene.js:4369): an update error is caught by
    // tryAndCatchError, which raises renderError and returns normally.
    render(time) {
      this.drawn += 1;
      this.preUpdate.raiseEvent(this, time);
      if (this.broken) this.renderError.raiseEvent(this, new Error('boom'));
      this.preRender.raiseEvent(this, time);
      this.postRender.raiseEvent(this, time);
    },
  };
  return { scene, ...renderLoopFixture(scene, { targetFrameRate }) };
}

for (const targetFrameRate of [undefined, 60]) {
  test(`targetFrameRate ${targetFrameRate}: Retry before the next frame after an error Scene caught keeps one render loop`, () => {
    const { frames, scene, viewer, store, runFrames, restore } = setup({
      targetFrameRate,
    });
    try {
      viewer.useDefaultRenderLoop = true;
      runFrames(2);
      scene.broken = true;
      runFrames(1);
      assert.equal(store.renderFailure?.reason, 'render-error');
      // The cause is gone; Retry runs (a queued Enter on the focused Retry)
      // before the loop's next animation frame.
      scene.broken = false;
      store.renderFailure.retry();
      assert.equal(frames.length, 1, 'one animation frame queued after Retry');
      scene.drawn = 0;
      runFrames(3);
      assert.equal(store.renderFailure, null);
      assert.equal(scene.drawn, 3, 'the globe draws once a frame');
    } finally {
      restore();
    }
  });
}

test('control: Retry after the next frame ran keeps one render loop', () => {
  const { frames, scene, viewer, store, runFrames, restore } = setup();
  try {
    viewer.useDefaultRenderLoop = true;
    runFrames(2);
    scene.broken = true;
    runFrames(1);
    scene.broken = false;
    runFrames(1);
    assert.equal(frames.length, 0, 'the stopped loop queued nothing');
    store.renderFailure.retry();
    scene.drawn = 0;
    runFrames(3);
    assert.equal(scene.drawn, 3);
  } finally {
    restore();
  }
});

test('a tab hidden and shown again before the next frame after an error Scene caught keeps one render loop', () => {
  const { scene, viewer, runFrames, restore } = setup();
  try {
    viewer.useDefaultRenderLoop = true;
    runFrames(2);
    scene.broken = true;
    runFrames(1);
    scene.broken = false;
    // src/app/tools.js turns the loop off while the tab is hidden and back on
    // when it is shown, before the queued frame runs.
    viewer.useDefaultRenderLoop = false;
    viewer.useDefaultRenderLoop = true;
    scene.drawn = 0;
    runFrames(3);
    assert.equal(scene.drawn, 3, 'the globe draws once a frame');
  } finally {
    restore();
  }
});

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

// A widget on Cesium's real CesiumWidget.prototype (startRenderLoop, the
// useDefaultRenderLoop setter, render) around a scene double, with animation
// frames queued by hand and the render failure notice installed.
import * as Cesium from 'cesium';
import { installRenderFailureNotice } from './renderFailure.js';

export function renderLoopFixture(
  scene,
  { targetFrameRate, viewer: viewerExtras = {}, notice = {} } = {},
) {
  const frames = [];
  const previousRaf = globalThis.requestAnimationFrame;
  globalThis.requestAnimationFrame = (fn) => frames.push(fn);
  const widget = Object.create(Cesium.CesiumWidget.prototype);
  Object.assign(widget, {
    _scene: scene,
    _clock: { tick() {} },
    _canRender: true,
    _useDefaultRenderLoop: false,
    _renderLoopRunning: false,
    // What src/app/scene.js passes to the viewer.
    _showRenderLoopErrors: false,
    _targetFrameRate: targetFrameRate,
    isDestroyed: () => false,
    resize() {},
  });
  // CesiumWidget's own renderError handler, which marks the loop stopped.
  scene.renderError.addEventListener(() => {
    widget._useDefaultRenderLoop = false;
    widget._renderLoopRunning = false;
  });
  const viewer = Object.assign(
    {
      scene,
      cesiumWidget: widget,
      canvas: { addEventListener() {}, removeEventListener() {} },
      get useDefaultRenderLoop() {
        return widget.useDefaultRenderLoop;
      },
      set useDefaultRenderLoop(value) {
        widget.useDefaultRenderLoop = value;
      },
    },
    viewerExtras,
  );
  const store = {
    renderFailure: null,
    publishRenderFailure(next) {
      this.renderFailure = next;
    },
  };
  const logged = [];
  const uninstall = installRenderFailureNotice(viewer, {
    store,
    locationRef: { href: 'https://gev.example/', reload() {}, assign() {} },
    logError: (error) => logged.push(error),
    ...notice,
  });
  let time = 0;
  const runFrames = (n) => {
    for (let i = 0; i < n; i += 1) {
      // Above a 60 fps target's interval, so every frame draws.
      time += 17;
      for (const fn of frames.splice(0)) fn(time);
    }
  };
  const restore = () => {
    uninstall();
    globalThis.requestAnimationFrame = previousRaf;
  };
  return { frames, widget, viewer, store, logged, runFrames, restore };
}

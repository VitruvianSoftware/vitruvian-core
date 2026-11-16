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

/**
 * Let a turned-off layer's memory go.
 *
 * A renderer may keep a turned-off layer's draw commands, and through them
 * its whole data source, reachable after the layer stops drawing: the
 * default renderer does (see `src/render/cesium/sceneCommandRelease.js`).
 * After a layer finishes turning off, this asks for one frame and, once it
 * is drawn, has the renderer trim what that frame no longer drew.
 */

/**
 * After every layer disable, render one frame and trim once it is drawn.
 * @param {{frame: import('./render/contract/frame').FramePort,
 *   dataManager: object, requestRender: (reason: string) => void,
 *   trim: () => void}} deps `trim` drops what the last drawn frame did not
 *   draw.
 * @returns {() => void} uninstall
 */
export function installLayerReleaseTrim({
  frame,
  dataManager,
  requestRender,
  trim,
}) {
  let removeOneShot = null;
  const unsubscribe = dataManager.subscribe((change) => {
    if (change?.type !== 'visibility' || change.enabled !== false) return;
    if (removeOneShot) return; // a trim is already waiting for its frame
    removeOneShot = frame.on('postRender', () => {
      removeOneShot();
      removeOneShot = null;
      trim();
    });
    requestRender('layer-release-trim');
  });
  return () => {
    unsubscribe();
    removeOneShot?.();
    removeOneShot = null;
  };
}

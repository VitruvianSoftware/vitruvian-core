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
 * A frame port over a fake Cesium scene, for tests of code that steers the
 * render loop through `renderGovernor.js`. It writes the scene the way the
 * Cesium port does (`src/render/cesium/ports.js`): holds, counted per
 * reason, keep `requestRenderMode` false; releasing the last asks for one
 * frame; a request is the scene's `requestRender`; the first hold and the
 * last release are told to `onHeldChange`; a rate set is kept as the
 * scene's `targetFps`. Only the members the governor uses. One port per
 * scene, so a test can uninstall what it installed.
 * @param {{requestRenderMode?: boolean, requestRender?: () => void}} scene
 */
export function framePortFor(scene) {
  let port = ports.get(scene);
  if (!port) ports.set(scene, (port = makePort(scene)));
  return port;
}

const ports = new WeakMap();

function makePort(scene) {
  const holds = new Map();
  const heldListeners = new Set();
  let wasHeld = false;
  const apply = () => {
    const held = holds.size > 0;
    scene.requestRenderMode = !held;
    if (held === wasHeld) return;
    wasHeld = held;
    for (const cb of [...heldListeners]) cb(held);
  };
  apply();
  return {
    onHeldChange(cb) {
      heldListeners.add(cb);
      return () => heldListeners.delete(cb);
    },
    diagnostics: () => ({ holds: [...holds.keys()] }),
    setTargetFps(fps) {
      scene.targetFps = fps;
    },
    requestRender() {
      scene.requestRender?.();
    },
    holdContinuous(reason) {
      holds.set(reason, (holds.get(reason) ?? 0) + 1);
      apply();
      let released = false;
      return () => {
        if (released) return;
        released = true;
        const left = holds.get(reason) - 1;
        if (left > 0) holds.set(reason, left);
        else holds.delete(reason);
        apply();
        if (holds.size === 0) scene.requestRender?.();
      };
    },
  };
}

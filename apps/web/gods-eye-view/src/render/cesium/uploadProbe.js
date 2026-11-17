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
 * @module render/cesium/uploadProbe
 * @description A QA probe: the bytes the WebGL context is handed
 * (`bufferData`, `bufferSubData`) while the hosts of some draw sets update,
 * frame by frame. A layer's frame probe takes it as its `uploads` (the
 * transit layer's `_measureTransitFramesForTest`), so the layer itself
 * stays off the default renderer. Diagnostics only: it wraps the context's
 * methods and the hosts' `update` until `stop()`.
 */
import { webglContext } from './internals.js';

/**
 * Count the bytes uploaded while the hosts of `setIds` update. Hosts are
 * found by the `drawSetId` the draw port names them with, again at each
 * `reset()`, so a host a rebuild puts in a set's place is counted too.
 * @param {object} viewer A Cesium viewer.
 * @param {readonly string[]} setIds
 * @returns {{reset: () => void, bytes: () => number, stop: () => void}}
 */
export function countDrawSetUploads(viewer, setIds) {
  const scene = viewer.scene;
  const ids = new Set(setIds);
  const gl = webglContext(scene);
  let active = false;
  let upload = 0;
  const restores = [];
  if (gl) {
    for (const name of ['bufferData', 'bufferSubData']) {
      const original = gl[name];
      gl[name] = function (...args) {
        if (active) {
          const value = args[name === 'bufferData' ? 1 : 2];
          const offset = args[3] || 0;
          const length = args[4];
          upload +=
            typeof value === 'number'
              ? value
              : value
                ? length !== undefined
                  ? length * (value.BYTES_PER_ELEMENT || 1)
                  : value.byteLength - offset * (value.BYTES_PER_ELEMENT || 1)
                : 0;
        }
        return original.apply(this, args);
      };
      restores.push(() => {
        gl[name] = original;
      });
    }
  }
  // Hosts wrapped so far, and how to give each its own `update` back (an
  // inherited one by deleting the wrapper).
  const wrapped = new Map();
  function wrapHosts() {
    const primitives = scene.primitives;
    for (let i = 0; i < (primitives?.length ?? 0); i++) {
      const host = primitives.get(i);
      if (!ids.has(host?.drawSetId) || wrapped.has(host)) continue;
      const original = host.update;
      const own = Object.prototype.hasOwnProperty.call(host, 'update');
      host.update = function (frameState) {
        active = true;
        try {
          return original.call(this, frameState);
        } finally {
          active = false;
        }
      };
      wrapped.set(host, { original, own, wrapper: host.update });
    }
  }
  wrapHosts();
  return {
    reset() {
      upload = 0;
      wrapHosts();
    },
    bytes: () => upload,
    stop() {
      for (const restore of restores) restore();
      restores.length = 0;
      for (const [host, { original, own, wrapper }] of wrapped) {
        // A host whose update was replaced meanwhile keeps the new one.
        if (host.update !== wrapper) continue;
        if (own) host.update = original;
        else delete host.update;
      }
      wrapped.clear();
    },
  };
}

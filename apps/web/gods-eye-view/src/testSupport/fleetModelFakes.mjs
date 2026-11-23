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

// Fleet models for a layer test (fleetModelInstances.js): the project's model
// set loaded from public/, a DISPLAY 3D toggle that is on, and the layer's
// draw port (testSupport/fakeDrawPort.mjs) answering each model's load.
import { loadFleetModelSet } from '../data/fleetModels.js';
import { fetchPublicFile } from './fleetGlb.mjs';

/** A model policy whose eligibility is read again on every frame. */
export const FLEET_TEST_POLICY = Object.freeze({
  altitudeCeilingM: 800_000,
  cap: 4,
  capAll: 8,
  addM: 5_000,
  keepM: 6_000,
  intervalMs: 0,
});

/**
 * Load the fleet set (once a process, as the app does). Call it before the
 * layer's harness, which replaces `fetch`; then `watch` the harness's draw
 * port.
 * @returns {Promise<{fleet: object, watch: (draw: object) => void,
 *   load: () => void, drawn: (id: string) => object[]}>} `fleet` for the
 *   layer's services; `load()` finishes the load of every model the layer
 *   has asked for, as the renderer does off the frame; `drawn(id)` the
 *   models drawn for the vehicle `id` now.
 */
export async function fleetModelFakes() {
  const info = console.info;
  console.info = () => {};
  try {
    await loadFleetModelSet({ fetchImpl: fetchPublicFile });
  } finally {
    console.info = info;
  }
  let draw = null;
  const sets = () =>
    draw
      ? [...draw.sets.values()].filter(
          (set) =>
            !set.disposed &&
            set.kind === 'models' &&
            set.spec.id.startsWith('fleet-models:'),
        )
      : [];
  return {
    fleet: {
      policy: FLEET_TEST_POLICY,
      display: () => ({ models3d: true, models3dMode: 'proximity' }),
      resolveAsset: (url) => url,
    },
    watch(port) {
      draw = port;
    },
    load() {
      for (const set of sets())
        for (const id of [...set.items.keys()]) draw.ready(set.spec.id, id);
    },
    drawn: (id) =>
      sets().flatMap((set) => {
        const item = set.items.get(id);
        return item && item.show !== false && set.show ? [item] : [];
      }),
  };
}

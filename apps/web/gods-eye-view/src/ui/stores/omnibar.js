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

import { defineStore } from 'pinia';
import { markRaw, shallowRef } from 'vue';

/**
 * The top-bar omnibar's link to the shell. The shell connects the actions
 * the omnibar offers: `layers()` lists the data layers as `{id, name,
 * enabled}`, and `setLayer(id, enabled)` turns one on or off as a user click
 * would. `creditPlaces()`, optional, credits the bundled Wikidata place
 * packs once a name from them is shown, and `creditSuggestions(shown)`,
 * optional, shows the OpenStreetMap credit while Photon's suggestions are. Place search runs through the
 * location controls and Ask GEV through the voice controls, so neither is
 * repeated here.
 */
export const useOmnibarStore = defineStore('gev-omnibar', () => {
  /** `{layers(), setLayer(id, enabled), creditPlaces?()}`, or null while disconnected. */
  const controls = shallowRef(null);

  /** @param {?object} next The shell's omnibar actions, or null. */
  function connect(next) {
    controls.value = next && markRaw(next);
  }

  /**
   * The voice action runner, `(name, args) → Promise<result>`: the same
   * actions voice and chat call, run directly without a model. Null while no
   * voice runtime is up.
   */
  const runner = shallowRef(null);

  /** @param {?Function} next The runner, or null to disconnect. */
  function connectRunner(next) {
    runner.value = next ? markRaw(next) : null;
  }

  return { controls, connect, runner, connectRunner };
});

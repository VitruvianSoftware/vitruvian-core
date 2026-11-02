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
import { computed, ref, shallowReactive } from 'vue';
import { createOwners } from './owners.js';

/**
 * The top-center globe actions as their view renders them, and the cockpit's
 * reset. The shell publishes whether a clear of the selected data layers or a
 * reset to the full globe view is under way and the camera's tilt and
 * heading, and answers the buttons through act().
 */
export const useGlobeActionsStore = defineStore('gev-globe-actions', () => {
  const owners = createOwners();
  // Who answers which action, as the computed state below reads it.
  const ownership = ref(0);

  /**
   * Whether the work behind an action is under way, kept per owner so its
   * button shows the owner that answers it; null until that owner says.
   */
  function ownedBusy(name) {
    const byOwner = shallowReactive(new Map());
    const busy = computed(() => {
      void ownership.value;
      return byOwner.get(owners.ownerOf(name)) ?? null;
    });
    /**
     * @param {object} token The owner's, from connect().
     * @param {boolean} value
     */
    const publish = (token, value) => {
      byOwner.set(token, Boolean(value));
    };
    return { byOwner, busy, publish };
  }
  const clearing = ownedBusy('clear');
  const resetting = ownedBusy('reset');
  /** Whether a clear of the selected data layers is under way. */
  const clearBusy = clearing.busy;
  const publishClearBusy = clearing.publish;
  /** Whether a reset to the full globe view is under way. */
  const resetBusy = resetting.busy;
  const publishResetting = resetting.publish;

  /**
   * Whether the map reads as tilted and the camera's whole-degree heading;
   * null until the camera controls first say.
   * @type {import('vue').Ref<{ tilted: boolean, heading: number } | null>}
   */
  const camera = ref(null);

  /**
   * Take the camera's state; the same state again changes nothing, so its
   * owner can publish it on every frame the camera draws.
   * @param {{ tilted: boolean, heading: number } | null} state
   */
  function publishCamera(state) {
    const current = camera.value;
    if (!state) {
      camera.value = null;
      return;
    }
    const tilted = Boolean(state.tilted);
    if (current?.tilted === tilted && current.heading === state.heading) return;
    camera.value = { tilted, heading: state.heading };
  }

  /** @param {Record<string, Function>} actions */
  function connect(actions) {
    const token = owners.connect(actions);
    ownership.value += 1;
    return token;
  }

  function detach(token) {
    owners.detach(token);
    clearing.byOwner.delete(token);
    resetting.byOwner.delete(token);
    ownership.value += 1;
  }

  const { act, owns } = owners;

  return {
    clearBusy,
    publishClearBusy,
    resetBusy,
    publishResetting,
    camera,
    publishCamera,
    connect,
    detach,
    act,
    owns,
  };
});

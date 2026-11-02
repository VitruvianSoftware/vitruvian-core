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
 * @typedef {object} StreetLevelHandlers
 * @property {(stop: number) => void} setSinceStop Record a SINCE stop.
 * @property {(stop: number) => string} describeSinceStop A stop's readout.
 */

/**
 * The Street Level panel as its view renders it. StreetLevelControls owns
 * the presentation (`presentStreetLevelPanel()`), the viewer and EXPAND: it
 * publishes here and attaches the actions the view forwards.
 */
export const useStreetLevelStore = defineStore('gev-street-level', () => {
  /** The presented panel; null until an owner renders, then its last render. */
  const view = shallowRef(null);
  /** Whether EXPAND has the viewer full screen; null until first synced. */
  const expanded = shallowRef(null);
  /** False on a page with neither element fullscreen nor popovers. */
  const expandAvailable = shallowRef(true);
  /** @type {{handlers: StreetLevelHandlers}|null} */
  let owner = null;

  /**
   * Present the panel for an owner, replacing any earlier owner.
   * @param {StreetLevelHandlers} handlers
   * @returns {object} Token for detach().
   */
  function attach(handlers) {
    owner = { handlers };
    return owner;
  }

  /** @param {object} next A fresh presentation; every publish re-renders. */
  function publish(next) {
    view.value = markRaw(next);
  }

  /** @param {boolean} on */
  function setExpanded(on) {
    expanded.value = Boolean(on);
  }

  /** @param {boolean} available */
  function setExpandAvailable(available) {
    expandAvailable.value = Boolean(available);
  }

  /**
   * Stop forwarding actions to the owner holding `token`. The panel keeps
   * its last render, as the page did when its controls were wired by hand.
   */
  function detach(token) {
    if (owner === token) owner = null;
  }

  /** Forward a view action to the owner. */
  function act(name, ...args) {
    owner?.handlers[name]?.(...args);
  }

  /** The readout of a SINCE stop while its thumb is dragged. */
  function describeSinceStop(stop) {
    return owner?.handlers.describeSinceStop?.(stop) ?? '';
  }

  return {
    view,
    expanded,
    expandAvailable,
    attach,
    publish,
    setExpanded,
    setExpandAvailable,
    detach,
    act,
    describeSinceStop,
  };
});

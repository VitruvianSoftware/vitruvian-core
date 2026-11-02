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
 * The Context panel's mode switch as its view renders it. ContextControls
 * presents the selected mode, the transition busy state and the nearby
 * sites search (`_presentContext()`) and publishes them here; it
 * keeps its listeners and transactions. The Contacts and Space Missions
 * layers publish their panels beside it, and the app connects each layer's
 * commands.
 */
export const useContextStore = defineStore('gev-context', () => {
  /** The presented mode switch; null until the controls first render. */
  const view = shallowRef(null);

  /** @param {object} next A fresh presentation; every publish re-renders. */
  function publish(next) {
    view.value = markRaw(next);
  }

  /** The Contacts panel; null until the layer first publishes. */
  const awareness = shallowRef(null);

  /** @param {object} next A fresh presentation of the Contacts panel. */
  function publishAwareness(next) {
    awareness.value = next && markRaw(next);
  }

  /**
   * The Contacts layer whose navigation the panel calls: `navigatePrevious`,
   * `focusCurrent`, `navigateNext` and `focusTarget`.
   */
  const awarenessLayer = shallowRef(null);

  /** @param {?object} layer The Contacts layer, or null to disconnect. */
  function connectAwareness(layer) {
    awarenessLayer.value = layer && markRaw(layer);
  }

  /** The Space Missions roster; null until the layer first presents it. */
  const missionRoster = shallowRef(null);

  /** The selected space mission; null while none is selected. */
  const mission = shallowRef(null);

  /**
   * @param {?{roster: ?object, mission: ?object}} next The layer's view. The
   *   layer keeps an unchanged roster's object, which re-renders nothing.
   */
  function publishMissions(next) {
    missionRoster.value = next?.roster ? markRaw(next.roster) : null;
    mission.value = next?.mission ? markRaw(next.mission) : null;
  }

  /** The Space Missions layer whose panel commands the components call. */
  const missionsLayer = shallowRef(null);

  /** @param {?object} layer The Space Missions layer, or null to disconnect. */
  function connectMissions(layer) {
    missionsLayer.value = layer && markRaw(layer);
  }

  return {
    view,
    publish,
    awareness,
    publishAwareness,
    awarenessLayer,
    connectAwareness,
    missionRoster,
    mission,
    publishMissions,
    missionsLayer,
    connectMissions,
  };
});

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
 * @typedef {object} SceneRowHandlers
 * @property {(shotId: string) => void} select
 * @property {(sceneId: string, shotId: string, title: string) => void} rename
 * @property {(sceneId: string, shotId: string) => void} load
 * @property {(sceneId: string, shotId: string) => void} remove
 * @property {(sceneId: string) => void} selectScene The select's choice.
 * @property {(file: File) => Promise<void>|void} importFile A chosen file.
 * @property {() => void} create, deleteScene, capture, update, start, stop,
 *   next, export, download The panel's buttons.
 */

/**
 * The Scene panel's project list as the panel views render it. SceneControls
 * owns the project presentation: it publishes here and attaches the row
 * actions; the views only render and forward clicks.
 */
export const useSceneStore = defineStore('gev-scenes', () => {
  // Scenes arrive as fresh read-only copies; only replacing them re-renders.
  const scenes = shallowRef(markRaw([]));
  const selectedSceneId = shallowRef(null);
  const selectedShotId = shallowRef(null);
  // The select's choice, updated only when its options are rendered.
  const listedSceneId = shallowRef(null);
  // Counts option renders: each one re-applies the select's choice, which
  // the person may have changed since.
  const listedRevision = shallowRef(0);
  /**
   * The panel's buttons, status line, progress and runtime chip:
   * `{running, hasShots, disabled: {[button]: boolean}, status, progress,
   * runtime, playLabel}`, or null until an owner presents them.
   */
  const panel = shallowRef(null);

  /** @param {?object} next A fresh presentation; every publish re-renders. */
  function publishPanel(next) {
    panel.value = next && markRaw(next);
  }

  /** Whether an owner presents the project; until then the list is empty. */
  const attached = shallowRef(false);
  /** @type {{handlers: SceneRowHandlers}|null} */
  let owner = null;

  /**
   * Present the project for an owner, replacing any earlier owner.
   * @param {SceneRowHandlers} handlers
   * @returns {object} Token for detach().
   */
  function attach(handlers) {
    owner = { handlers };
    attached.value = true;
    return owner;
  }

  /** Publish the shot list; `scenes` is copied so every publish re-renders. */
  function publish(state) {
    scenes.value = markRaw([...(state.scenes ?? [])]);
    selectedSceneId.value = state.selectedSceneId ?? null;
    selectedShotId.value = state.selectedShotId ?? null;
  }

  /** Publish the project and the select's choice. */
  function publishOptions(state) {
    publish(state);
    listedSceneId.value = state.selectedSceneId ?? null;
    listedRevision.value++;
  }

  /** @param {string|null} id */
  function selectShot(id) {
    selectedShotId.value = id ?? null;
  }

  /**
   * Stop presenting for the owner holding `token`: the list empties and row
   * clicks do nothing. A later owner's presentation is left alone.
   */
  function detach(token) {
    if (token !== owner) return;
    owner = null;
    attached.value = false;
    publishOptions({});
  }

  /** @returns {boolean} Whether `token` is the owner presenting now. */
  function owns(token) {
    return !!token && token === owner;
  }

  /**
   * Forward a row action to the owner, if one is attached.
   * @param {keyof SceneRowHandlers} name
   * @returns {*} What the owner's handler returned (an import's promise).
   */
  function act(name, ...args) {
    return owner?.handlers[name]?.(...args);
  }

  return {
    scenes,
    selectedSceneId,
    selectedShotId,
    listedSceneId,
    listedRevision,
    attached,
    panel,
    publishPanel,
    attach,
    publish,
    publishOptions,
    selectShot,
    detach,
    owns,
    act,
  };
});

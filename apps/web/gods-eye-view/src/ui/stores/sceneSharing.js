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
 * Scene sharing as its views render it. The sharing owner
 * (src/scenes/sharing.js) offers the EDIT DETAILS / SHARE SCENE bar and
 * presents its one open dialog here; the views send clicks, typing and file
 * choices back to the connected dialog.
 */
export const useSceneSharingStore = defineStore('gev-scene-sharing', () => {
  /** The bar's actions ({edit, share}), or null while no owner offers it. */
  const toolbar = shallowRef(null);

  /** @param {?{edit: Function, share: Function}} next */
  function offerToolbar(next) {
    toolbar.value = next && markRaw(next);
  }

  /** The open dialog's presentation, or null while none is open. */
  const dialog = shallowRef(null);

  /** @param {?object} next A fresh presentation; every publish re-renders. */
  function publishDialog(next) {
    dialog.value = next && markRaw(next);
  }

  /** The open dialog the view calls, or null while none is wired. */
  const controls = shallowRef(null);

  /** @param {?object} next The dialog, or null to disconnect. */
  function connect(next) {
    controls.value = next && markRaw(next);
  }

  return { toolbar, offerToolbar, dialog, publishDialog, controls, connect };
});

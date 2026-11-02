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

import { t } from '../i18n/index.js';
import { useSceneSharingStore } from './stores/sceneSharing.js';
import { applicationPinia } from './vueRuntime.js';

let dialogCount = 0;

/**
 * Small owned modal for scene authoring and import review; text never becomes
 * markup. The dialog is presented through the scene sharing store and drawn
 * by SceneDialog.vue; the returned builder adds its lines, fields and buttons
 * in order. Body content comes first, then the status line, then the footer
 * row, which starts with Cancel.
 * @param {string} title
 * @param {() => void} onClose Cancel, Escape.
 */
export function createSceneDialog(
  title,
  onClose,
  store = useSceneSharingStore(applicationPinia()),
) {
  const id = ++dialogCount;
  const items = [];
  const actions = new Map();
  let status = '',
    statusSeq = 0,
    nextItem = 0,
    disposed = false;
  const controls = {
    click(itemId) {
      const item = items.find((entry) => entry.id === itemId);
      if (!disposed && !item?.disabled) actions.get(itemId)?.();
    },
    setValue(itemId, value) {
      const item = items.find((entry) => entry.id === itemId);
      if (item) item.value = value;
    },
    setFiles(itemId, files) {
      const item = items.find((entry) => entry.id === itemId);
      if (!item) return;
      item.files = [...files];
      publish();
    },
    cancel() {
      if (!disposed) onClose();
    },
  };
  function publish() {
    if (disposed || store.controls !== controls) return;
    store.publishDialog({
      id,
      title,
      items: items.map((item) => ({ ...item })),
      status,
      statusSeq,
    });
  }
  function add(item) {
    items.push({ id: nextItem++, ...item });
    publish();
    return items.at(-1);
  }
  function text(value) {
    add({ kind: 'text', place: 'body', value });
  }
  /**
   * @param {string} label
   * @param {() => void} fn
   * @param {object} [options]
   * @param {'body'|'footer'} [options.place]
   * @param {string} [options.hook] A data attribute name, e.g.
   *   'data-director-apply-import', for automation to find the button by.
   * @returns {{disabled: boolean}}
   */
  function button(label, fn, { place = 'footer', hook, autofocus } = {}) {
    const item = add({
      kind: 'button',
      place,
      label,
      disabled: false,
      hook,
      autofocus,
    });
    actions.set(item.id, fn);
    return {
      get disabled() {
        return item.disabled;
      },
      set disabled(value) {
        item.disabled = Boolean(value);
        publish();
      },
    };
  }
  /**
   * @param {string} label
   * @param {string} value
   * @param {object} [options]
   * @param {string} [options.type]
   * @param {boolean} [options.multiline]
   * @param {boolean} [options.multiple] File inputs: several files.
   * @param {boolean} [options.directory] File inputs: a whole folder.
   * @returns {{value: string, readonly files: File[]}}
   */
  function input(
    label,
    value,
    { type = 'text', multiline = false, multiple, directory } = {},
  ) {
    const item = add({
      kind: 'input',
      place: 'body',
      label,
      value,
      type: multiline ? null : type,
      multiline,
      multiple: Boolean(multiple),
      directory: Boolean(directory),
      files: [],
    });
    return {
      get value() {
        return item.value;
      },
      set value(next) {
        item.value = next;
        publish();
      },
      get files() {
        return item.files;
      },
    };
  }
  function setStatus(value) {
    status = value;
    statusSeq++;
    publish();
  }
  store.connect(controls);
  // Cancel takes the opening focus, as the first control drawn.
  button(t('Cancel'), onClose, { autofocus: true });
  return {
    text,
    button,
    input,
    setStatus,
    dispose() {
      if (disposed) return;
      if (store.controls === controls) {
        store.connect(null);
        store.publishDialog(null);
      }
      disposed = true;
    },
  };
}

/**
 * Offer the EDIT DETAILS / SHARE SCENE bar beside the scene panel's file
 * controls; the returned function withdraws it, unless another owner has
 * offered its own since.
 */
export function mountSceneSharing(
  { edit, share },
  store = useSceneSharingStore(applicationPinia()),
) {
  const actions = { edit, share };
  store.offerToolbar(actions);
  return () => {
    if (store.toolbar === actions) store.offerToolbar(null);
  };
}

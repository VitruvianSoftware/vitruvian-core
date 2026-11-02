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

import { useStatusStore } from './stores/status.js';
import { applicationPinia } from './vueRuntime.js';

// Counts every show on the page, so a repeated message is announced again.
let shown = 0;

/**
 * One owner's use of the page toast, which the scene chrome renders from the
 * status store. Each owner keeps its own timer, so a later toast from another
 * owner is hidden when this one's time is up, as the shared element was.
 * @param {object} options
 * @param {number} options.durationMs How long a toast stays up.
 * @param {object} [options.store] The status store.
 */
export function createToast({
  durationMs,
  store = useStatusStore(applicationPinia()),
}) {
  let timer = null;
  // The text stays while the toast fades out.
  const hide = () => {
    clearTimeout(timer);
    timer = null;
    if (store.toast?.visible)
      store.publishToast({ ...store.toast, visible: false });
  };
  return {
    /** @param {string} message */
    show(message) {
      store.publishToast({ text: message, visible: true, shown: ++shown });
      clearTimeout(timer);
      timer = setTimeout(hide, durationMs);
    },
    /** Hide the toast now and drop the timer. */
    hide,
    /** Drop the timer, leaving the toast as it is. */
    cancel() {
      clearTimeout(timer);
      timer = null;
    },
  };
}

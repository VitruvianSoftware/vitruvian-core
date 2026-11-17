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
 * Groups of controls added to the Display panel, under
 * Effects: toggles, sliders and notes, each answered by whoever added it.
 */
import { applicationPinia } from './vueRuntime.js';
import { useDisplayStore } from './stores/display.js';

/**
 * Show the group `id` on the page's Display panel as `group` describes it,
 * in place where it is shown already; null takes it away. A row is a
 * `toggle` (`{kind, id, label, icon?, title?, checked, onChange(checked)}`),
 * a `slider` (`{kind, id, label, min, max, value, onChange(value)}`, its
 * value shown in percent) or a `note` (`{kind, id, text}`). Publish it again
 * whenever what it shows changes.
 * @param {string} id
 * @param {?{rows: object[]}} group
 */
export function publishDisplayGroup(id, group) {
  useDisplayStore(applicationPinia()).publishGroup(id, group);
}

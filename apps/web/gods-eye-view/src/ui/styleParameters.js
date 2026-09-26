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
 * Own generated parameter rows and their input listeners.
 * The caller supplies uniform metadata/value access and rendering/persistence
 * callbacks. Replacing or destroying rows revokes all old input handlers.
 * @param {object} options
 * @param {HTMLElement} options.container Container owned by this component.
 * @param {Document} [options.documentRef] Document used to construct rows.
 * @returns {{render: Function, clear: Function, destroy: Function}}
 */
export function createStyleParameters({
  container,
  documentRef = container.ownerDocument,
}) {
  let listeners = [];
  let destroyed = false;
  const clear = () => {
    if (destroyed) return;
    for (const [slider, listener] of listeners)
      slider.removeEventListener('input', listener);
    listeners = [];
    container.replaceChildren();
  };
  return {
    /** Render uniform metadata with readValue, writeValue and onChange callbacks. */
    render({ uniforms, readValue, writeValue, onChange }) {
      if (destroyed) return;
      clear();
      for (const [name, metadata] of Object.entries(uniforms)) {
        const row = documentRef.createElement('div');
        row.className = 'param-slider-row';
        const label = documentRef.createElement('span');
        label.className = 'param-label';
        label.textContent = metadata.label;
        const slider = documentRef.createElement('input');
        slider.type = 'range';
        slider.className = 'param-slider';
        slider.setAttribute('aria-label', metadata.label);
        slider.min = metadata.min;
        slider.max = metadata.max;
        slider.step = metadata.max <= 1 ? '0.01' : '0.1';
        slider.value = readValue(name);
        const digits = metadata.max <= 1 ? 2 : 1;
        const valueDisplay = documentRef.createElement('span');
        valueDisplay.className = 'param-value';
        valueDisplay.textContent = parseFloat(slider.value).toFixed(digits);
        const onInput = () => {
          const value = parseFloat(slider.value);
          writeValue(name, value);
          valueDisplay.textContent = value.toFixed(digits);
          onChange();
        };
        slider.addEventListener('input', onInput);
        listeners.push([slider, onInput]);
        row.append(label, slider, valueDisplay);
        container.appendChild(row);
      }
    },
    clear,
    destroy() {
      if (destroyed) return;
      clear();
      destroyed = true;
    },
  };
}

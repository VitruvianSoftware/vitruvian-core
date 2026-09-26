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
 * Bind Display controls to application actions. Inputs remain native DOM controls;
 * the caller owns settings and effect state. Destroy before replacing the view.
 * @param {{ elements: object, actions: object }} options
 * @returns {{ destroy(): void }}
 */
export function bindDisplayControls({ elements, actions }) {
  const removers = [];
  const listen = (element, type, action, read) => {
    if (!element) return;
    const handler = () => actions[action](...(read ? [read(element)] : []));
    element.addEventListener(type, handler);
    removers.push(() => element.removeEventListener(type, handler));
  };
  const integer = (element) => parseInt(element.value, 10);
  for (const [name, action] of [
    ['bloomButton', 'toggleBloom'],
    ['sharpenButton', 'toggleSharpen'],
    ['scopeButton', 'toggleScope'],
    ['cleanViewButton', 'toggleCleanView'],
    ['cleanViewExitButton', 'exitCleanView'],
    ['celestialButton', 'toggleCelestial'],
    ['hudButton', 'toggleHud'],
    ['sonarButton', 'toggleSonar'],
    ['detectionButton', 'cycleDetection'],
    ['modelsButton', 'toggleModels'],
  ])
    listen(elements[name], 'click', action);
  for (const [name, action] of [
    ['bloomSlider', 'setBloomIntensity'],
    ['sharpenSlider', 'setSharpenIntensity'],
    ['scopeFeatherSlider', 'setScopeFeather'],
  ])
    listen(elements[name], 'input', action, integer);
  listen(elements.densitySlider, 'input', 'setDensity', (el) => el.value);
  listen(elements.hudLayout, 'change', 'setHudLayout', (el) => el.value);
  for (const [name, action] of [
    ['sonarRingsSlider', 'setSonarRings'],
    ['sonarRangeSlider', 'setSonarRange'],
    ['sonarIntensitySlider', 'setSonarIntensity'],
    ['sonarOpacitySlider', 'setSonarOpacity'],
    ['sonarSectorSlider', 'setSonarSector'],
  ])
    listen(elements[name], 'input', action, integer);
  for (const el of elements.styleButtons || [])
    listen(el, 'click', 'setStyle', (el) => el.dataset.style);
  for (const el of elements.allocationButtons || [])
    listen(el, 'click', 'setAllocation', (el) => el.dataset.allocation);
  for (const el of elements.modelModeButtons || [])
    listen(el, 'click', 'setModelsMode', (el) =>
      el.dataset.mode === 'all' ? 'all' : 'proximity',
    );
  for (const el of elements.fadeSliders || []) listen(el, 'input', 'setFade');
  return {
    destroy() {
      for (const remove of removers.splice(0)) remove();
    },
  };
}

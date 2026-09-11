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

export const COCKPIT_VISION_MODES = Object.freeze(['optical', 'crt', 'nvg', 'thermal', 'noir']);

const TARGET_STYLE_BY_MODE = Object.freeze({
  crt: 'retro',
  nvg: 'surveillance',
  thermal: 'thermal',
  noir: 'noir',
});

/** Normalize a requested Cockpit vision mode to the inherited preset entry. */
export function normalizeCockpitVisionMode(mode) {
  return COCKPIT_VISION_MODES.includes(mode) ? mode : 'optical';
}

/** Settle pending map-style crossfades and return their intended final intensities. */
export function captureCockpitVisionBaseline(stages, transitions) {
  const baseline = {};
  for (const [name, stage] of Object.entries(stages)) {
    const intensity = transitions?.get(name)?.to ?? stage.uniforms.intensity;
    stage.uniforms.intensity = intensity;
    transitions?.delete(name);
    baseline[name] = intensity;
  }
  return baseline;
}

/**
 * Apply Cockpit-only stage intensities without changing any shader parameters.
 * Returns the temporary style whose parameters should be shown, or null.
 */
export function applyCockpitVisionStageIntensities(stages, mode, restore = {}) {
  const next = normalizeCockpitVisionMode(mode);
  if (next === 'optical') {
    for (const [name, intensity] of Object.entries(restore)) {
      if (stages[name]) stages[name].uniforms.intensity = intensity;
    }
    return null;
  }

  for (const stage of Object.values(stages)) stage.uniforms.intensity = 0;
  const target = TARGET_STYLE_BY_MODE[next] || null;
  if (target && stages[target]) stages[target].uniforms.intensity = 1;
  return target;
}

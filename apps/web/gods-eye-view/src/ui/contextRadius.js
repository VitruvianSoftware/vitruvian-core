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

import { ref } from 'vue';

// How far out Context looks for what is "nearby": one distance for every
// nearby block (flights, vessels, hazards, alerts, other loaded items). The
// control in the Context panel steps through a few distances; the choice is
// kept for the next visit.
const KEY = 'gev.contextRadiusKm';

/** The distances the control steps through, in km. */
export const CONTEXT_RADIUS_STEPS = Object.freeze([
  25, 50, 100, 250, 500, 1000, 2500,
]);
export const DEFAULT_CONTEXT_RADIUS_KM = 250;

/** The step closest to a distance; the default for anything unusable. */
export function nearestRadiusStep(km) {
  const value = Number(km);
  if (!Number.isFinite(value) || value <= 0) return DEFAULT_CONTEXT_RADIUS_KM;
  return CONTEXT_RADIUS_STEPS.reduce((best, step) =>
    Math.abs(step - value) < Math.abs(best - value) ? step : best,
  );
}

function read() {
  try {
    const saved = globalThis.localStorage?.getItem(KEY);
    return saved === null || saved === undefined
      ? DEFAULT_CONTEXT_RADIUS_KM
      : nearestRadiusStep(saved);
  } catch {
    return DEFAULT_CONTEXT_RADIUS_KM;
  }
}

/** The radius every nearby block uses, in km. */
export const contextRadiusKm = ref(read());

export function setContextRadiusKm(km) {
  contextRadiusKm.value = nearestRadiusStep(km);
  try {
    globalThis.localStorage?.setItem(KEY, String(contextRadiusKm.value));
  } catch {
    // Without storage the choice lasts for this visit.
  }
}

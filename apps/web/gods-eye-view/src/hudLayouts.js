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

import { applyCyberSonarThemePhase } from './cyberSonar.js';
import { syncRadioPanelPlacement } from './ui/radioPanelPlacement.js';
import { HUD_LAYOUTS } from './hudLayoutPolicy.js';
export { HUD_LAYOUTS } from './hudLayoutPolicy.js';

/** Canonical HUD layouts shared by the UI, voice schema and HUD renderer. */

export const DEFAULT_HUD_LAYOUT = 'tactical';

/** Visual treatment applied only when an operator explicitly enters Cyber. */
export const CYBER_VISUAL_DEFAULTS = Object.freeze({
  style: 'thermal',
  ironbow: 0.42,
});

const HUD_LAYOUT_SET = new Set(HUD_LAYOUTS);

/** @param {unknown} value */
export function isHudLayout(value) {
  return HUD_LAYOUT_SET.has(String(value ?? '').toLowerCase());
}

/** @param {unknown} value */
export function normalizeHudLayout(value) {
  const normalized = String(value ?? '').toLowerCase();
  return isHudLayout(normalized) ? normalized : DEFAULT_HUD_LAYOUT;
}

/**
 * Resolve the opt-in visual defaults for an explicit layout transition.
 * Restores and repeated Cyber selections return null so they never overwrite
 * a shared link or a user's subsequent FLIR tuning.
 */
export function cyberVisualDefaultsForHudTransition(
  previousLayout,
  nextLayout,
  { explicit = false } = {},
) {
  if (!explicit) return null;
  if (normalizeHudLayout(previousLayout) === 'cyber') return null;
  if (normalizeHudLayout(nextLayout) !== 'cyber') return null;
  return CYBER_VISUAL_DEFAULTS;
}

/**
 * Keep the global shell skin derived from the selected HUD layout. The data
 * attribute lives on <html> so theme tokens are available to every UI surface.
 * @param {HTMLElement|{dataset?: Record<string, string>}|null|undefined} root
 * @param {unknown} layout
 * @returns {'cyber'|null}
 */
export function applyHudUiTheme(root, layout) {
  if (!root?.dataset) return null;
  if (normalizeHudLayout(layout) === 'cyber') {
    root.dataset.uiTheme = 'cyber';
    applyCyberSonarThemePhase(root, true);
    syncRadioPanelPlacement(root.ownerDocument);
    return 'cyber';
  }
  delete root.dataset.uiTheme;
  applyCyberSonarThemePhase(root, false);
  syncRadioPanelPlacement(root.ownerDocument);
  return null;
}

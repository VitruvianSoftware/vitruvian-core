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

// Solid chrome that card placement should avoid. It composites above the
// overlay; the host needs no paint mask. Cockpit line art is intentionally
// excluded so its large bounds cannot suppress world-space content.
export const WORLD_OVERLAY_OCCLUDER_SELECTORS = Object.freeze([
  '#title-bar',
  '#style-indicator',
  '#top-center-actions',
  '#traffic-sync-chip',
  '#cctv-sync-chip',
  '#left-panel-stack',
  '#right-context-rail',
  '.weather-summary',
  '#pp-toggles',
  '#command-dock',
  '#gev-voice-control',
  '#cesium-credits',
  '.hud-top-left',
  '.hud-top-right',
  '.hud-bottom-left',
  '.hud-bottom-right',
  '.hud-bottom-bar',
  '#space-mission-panel',
  '#space-mission-panel-host',
  '#military-awareness-panel',
  '#bhote-koshi-event-panel',
  // Only the cockpit's solid windows obstruct readable cards.
  '#cockpit-context',
  '#cockpit-signal-stream',
]);

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
 * While Stories is open its screens own the keyboard. A key pressed inside
 * Stories reaches Stories' controls and stops at its root, before GEV's
 * document-level shortcuts; a key pressed anywhere else (nothing focused, or
 * a hidden GEV control) stops at the window, so nothing behind Stories acts
 * on it, unless it is one of a playing GEV scene's own on-globe controls.
 * Listeners on the window itself (Stories' own Escape and "/") still
 * run. Capture-phase listeners on the document run before the root and check
 * `body.stories-mode` themselves (hold Space to talk, focus traps).
 * @param {{root: HTMLElement, isOpen: () => boolean, win?: Window}} options
 * @returns {() => void} Removes the guard.
 */
export function guardStoriesKeyboard({ root, isOpen, win = window }) {
  const types = ['keydown', 'keyup', 'keypress'];
  // A GEV scene playing in Stories keeps its own controls (the A/B slider,
  // an embedded player's card): their keys reach them as outside Stories.
  const sceneControl = (target) =>
    root.ownerDocument.body.classList.contains('stories-scene') &&
    !!target?.closest?.('[data-globe-overlay]');
  const outside = (event) => {
    if (!isOpen() || root.contains(event.target)) return;
    if (sceneControl(event.target)) return;
    event.stopPropagation();
  };
  const inside = (event) => {
    if (isOpen()) event.stopPropagation();
  };
  for (const type of types) {
    win.addEventListener(type, outside, true);
    root.addEventListener(type, inside);
  }
  return () => {
    for (const type of types) {
      win.removeEventListener(type, outside, true);
      root.removeEventListener(type, inside);
    }
  };
}

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

import { findFrame } from '../render/rendererOf.js';

/**
 * Draw the sky at the world time: the sun, moon, stars, atmosphere and the
 * lighting on the tiles all read the frame port's scene time, which never
 * moved on its own, so before this the sky stayed at the moment the page
 * loaded.
 *
 * Each frame's time is set in `preUpdate`, so the sky is drawn at the same
 * moment the layers read that frame.
 * @param {object} viewer
 * @param {() => number} readTime Epoch ms the sky is drawn at.
 * @param {{subscribe?: Function, requestRender?: () => void,
 *   onPlaying?: (playing: boolean) => void}} [options]
 *   A world clock to hear moves from, so a resting scene repaints when the
 *   world time jumps. `onPlaying` hears when the world clock starts and stops
 *   playing away from live (not stepped by a driver and not waiting for a
 *   layer's data), so the scene can draw every frame meanwhile.
 * @returns {() => void} Stop following.
 */
export function followWorldTime(
  viewer,
  readTime,
  {
    subscribe,
    requestRender = () => findFrame(viewer)?.requestRender('world-time'),
    onPlaying = () => {},
  } = {},
) {
  let playing = false;
  const setPlaying = (next) => {
    if (next === playing) return;
    playing = next;
    onPlaying(next);
  };
  const frame = findFrame(viewer);
  const off = frame?.on('preUpdate', () => frame.setTime(readTime())) ?? null;
  let last = readTime();
  const unsubscribe =
    subscribe?.((state) => {
      setPlaying(
        Boolean(
          state?.playing && !state.live && !state.stepping && !state.buffering,
        ),
      );
      const next = readTime();
      if (next === last) return;
      last = next;
      requestRender();
    }) ?? (() => {});
  return () => {
    off?.();
    unsubscribe();
    setPlaying(false);
  };
}

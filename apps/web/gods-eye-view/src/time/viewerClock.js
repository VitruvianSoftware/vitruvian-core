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

import * as Cesium from 'cesium';

/**
 * Draw Cesium's sky at the world time: the sun, moon, stars, atmosphere and
 * the lighting on the tiles all read `frameState.time`, which Cesium takes
 * from its own clock. That clock never animates in GEV, so before this the
 * sky stayed at the moment the page loaded.
 *
 * Each frame's time is set in `preUpdate`, before the scene stamps the frame
 * with it, so the sky is drawn at the same moment the layers read that frame.
 * The clock's `currentTime` follows too, for anything that samples it.
 * @param {Cesium.Viewer} viewer
 * @param {() => number} readTime Epoch ms the sky is drawn at.
 * @param {{subscribe?: Function, requestRender?: () => void}} [options]
 *   A world clock to hear moves from, so a resting scene repaints when the
 *   world time jumps.
 * @returns {() => void} Stop following.
 */
export function followWorldTime(
  viewer,
  readTime,
  { subscribe, requestRender = () => viewer.scene.requestRender() } = {},
) {
  const date = new Date();
  const removePreUpdate = viewer.scene.preUpdate.addEventListener(
    (_scene, time) => {
      date.setTime(readTime());
      const clock = viewer.clock;
      Cesium.JulianDate.fromDate(date, clock.currentTime);
      // The frame's own time: Cesium stamps the frame with this object next.
      if (time) Cesium.JulianDate.clone(clock.currentTime, time);
    },
  );
  let last = readTime();
  const unsubscribe =
    subscribe?.(() => {
      const next = readTime();
      if (next === last) return;
      last = next;
      requestRender();
    }) ?? (() => {});
  return () => {
    removePreUpdate();
    unsubscribe();
  };
}

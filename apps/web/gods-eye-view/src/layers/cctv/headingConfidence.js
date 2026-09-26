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
 * @module headingConfidence
 *
 * Consumers for the catalog's per-camera `headingConfidence` flag (#639).
 *
 * Packs whose feed publishes no facing get a synthetic bearing from
 * `fallbackHeadingFromId` — a hash of the id string, with no geographic
 * input — and are marked `headingConfidence: 'low'`. Until now nothing read
 * the flag, so a guessed bearing rendered exactly like a surveyed one. These
 * helpers make the guess visible: the HUD heading token gains an
 * `(ESTIMATED)` tag and the coverage wireframe draws dashed instead of solid.
 *
 * A human-vouched pose always wins over the pack flag: a manually saved
 * calibration (`calSource:'manual'`) or a hand-authored catalog entry
 * (`poseSource:'curated'`) is never presented as estimated, mirroring the
 * CAL badge states in calibration.js.
 */

/**
 * Whether a camera's bearing is a synthetic guess that should present as
 * provisional.
 * @param {{headingConfidence?: string|null, calSource?: string|null,
 *   poseSource?: string|null}} camera - Catalog camera (or public state).
 * @returns {boolean}
 */
export function isHeadingEstimated(camera) {
  if (!camera) return false;
  if (camera.calSource === 'manual') return false;
  if (camera.poseSource === 'curated') return false;
  return (
    String(camera.headingConfidence || '')
      .trim()
      .toLowerCase() === 'low'
  );
}

/**
 * HUD heading token: `HDG 194°`, tagged `(ESTIMATED)` when the bearing is
 * synthetic — so a hash can never read as a surveyed facing.
 * @param {{headingDeg?: number, headingConfidence?: string|null,
 *   calSource?: string|null, poseSource?: string|null}} camera
 * @returns {string}
 */
export function headingHudToken(camera) {
  const hdg = Math.round(Number(camera?.headingDeg) || 0);
  return `HDG ${hdg}°${isHeadingEstimated(camera) ? ' (ESTIMATED)' : ''}`;
}

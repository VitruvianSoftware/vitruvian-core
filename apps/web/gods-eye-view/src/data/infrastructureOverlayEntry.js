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

const LOCAL_OVERLAY_MAX_DISTANCE_M = 14000000;
const LOCAL_OVERLAY_FADE_START_M = 250000;
const LOCAL_OVERLAY_FADE_START_RATIO =
  LOCAL_OVERLAY_FADE_START_M / LOCAL_OVERLAY_MAX_DISTANCE_M;

/** Shared ambient infrastructure card contract; the host owns projection and persistence. */
export function createInfrastructureOverlayEntry({
  id,
  source,
  position,
  title,
  details = [],
  accent,
  priority,
}) {
  return {
    id: String(id),
    source: source,
    position,
    variant: 'card',
    title: title,
    details: details,
    accent,
    priority,
    collisionGroup: 'ambient-card',
    zIndex: 30,
    interactive: false,
    minDistance: 0,
    maxDistance: LOCAL_OVERLAY_MAX_DISTANCE_M,
    distanceFadeStartRatio: LOCAL_OVERLAY_FADE_START_RATIO,
    distanceScale: {
      near: 250000,
      nearValue: 1,
      far: 9000000,
      farValue: 0.62,
    },
    edgeFade: 'keyhole',
    horizonCull: true,
    terrainOcclusion: false,
    gapPx: 15,
    placement: 'above',
  };
}

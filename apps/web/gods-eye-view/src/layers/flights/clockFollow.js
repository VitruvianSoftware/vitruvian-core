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

import { forgetPlacedAircraft } from './placed.js';

/**
 * What the layer drops when the world clock moves it to another time (its
 * source declares a timeline; see src/time/snapshotTimeline.js).
 */
export function createClockFollow({ flightState, services, parts }) {
  /**
   * Forget how every contact moved, before the snapshot at another time takes
   * the place of every contact: their fixes, courses, floors and the tracked
   * trail belong to the time the clock left.
   */
  function resetMotion() {
    forgetPlacedAircraft(
      services?.placement,
      flightState._positionHistory.keys(),
    );
    flightState.records.reset();
    flightState._positionHistory.clear();
    flightState._displayCourse.clear();
    flightState._groundSnap.clear();
    flightState._displayFloorState.clear();
    flightState._drReconcileValid = false;
    flightState._cachedDRFrame = -1;
    flightState._cachedDRPosition = null;
    parts.tracking._clearTrail();
    flightState._lastCamPoseSig = '';
  }

  /** Drop every contact: the time has none to show, or the clock went live. */
  function clear() {
    if (flightState._trackedIcao)
      parts.tracking._clearTracking(false, { evicted: true });
    resetMotion();
    // Each contact's icon row and 3D model go with it.
    for (const icao24 of [...(flightState._icons?.ids() ?? [])])
      parts.icons._forgetContact(icao24);
    flightState._detectionObjects.clear();
    flightState.feed._count = 0;
    flightState.feed._lastUpdate = null;
  }

  return { resetMotion, clear };
}

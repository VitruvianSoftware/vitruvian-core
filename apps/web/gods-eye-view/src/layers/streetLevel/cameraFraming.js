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

import { plausibleSurfaceHeight, sampledSurfaceHeight } from './view.js';
import { toRadians } from '../../geo/index.js';
import { cameraOf, findQuery } from '../../render/rendererOf.js';

/** Fly the globe camera once to frame a photo after it opens. */
export function createCameraFraming({ state }) {
  /**
   * The application's camera authority: `reassert(begin())` succeeds only if
   * nothing newer took the camera. Without it, framing flies directly.
   */
  let navigation = null;
  /** Our framing flight while it is current; Cesium calls `cancel` when another flight starts. */
  let flight = null;

  function attachNavigation(next) {
    navigation = next || null;
  }

  /** Ask for the camera as a photo starts opening: a ticket for `frame`, null when refused (cockpit). */
  function begin() {
    if (!navigation?.begin || !navigation.reassert) return { generation: null };
    const generation = navigation.begin('photo');
    return generation === false ? null : { generation };
  }

  /**
   * Ground under a photo. `sampleHeight` can return kilometres below the
   * ellipsoid before tiles load, so only a plausible height counts.
   */
  function groundHeightAt(lon, lat, fallback) {
    const viewer = state.viewer;
    const point = { lon, lat };
    let height = sampledSurfaceHeight(viewer, point);
    if (height === null && viewer)
      height =
        findQuery(viewer)?.sampleHeightNow(point, { against: 'terrain' }) ??
        null;
    if (!plausibleSurfaceHeight(height)) height = fallback;
    return plausibleSurfaceHeight(height) ? height : 0;
  }

  /**
   * Frame the open photo from a short distance behind it, unless another
   * action took the camera since `ticket` (from `begin`) was issued.
   */
  function frame(ticket) {
    const { position, bearing, altitude } = state.street;
    if (!ticket || !position || !state.viewer) return;
    // Detached (shell teardown) since the ticket was issued: nothing to frame for.
    if (ticket.generation !== null && !navigation?.reassert(ticket.generation))
      return;
    const ground = groundHeightAt(position.lon, position.lat, altitude);
    // Owned before the call: starting it cancels the previous flight (ours
    // included), and a zero-length one completes inside the call.
    const current = {};
    flight = current;
    const release = () => {
      if (flight === current) flight = null;
    };
    const started = cameraOf(state.viewer).flyToBounds(
      {
        center: { lon: position.lon, lat: position.lat, height: ground + 2 },
        radius: 4,
      },
      {
        offset: {
          heading: toRadians(bearing || 0),
          pitch: toRadians(-32),
          range: 140,
        },
        durationS: 1.6,
        onComplete: release,
        onCancel: release,
      },
    );
    if (flight === current) current.handle = started;
  }

  /** Stop our framing flight if it is still in the air; another feature's flight is left alone. */
  function cancel() {
    if (!flight) return;
    const { handle } = flight;
    flight = null;
    handle?.cancel();
  }

  return { attachNavigation, begin, frame, cancel };
}

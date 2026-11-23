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

import { toRadians } from '../../geo/vector.js';
import { cameraOf } from '../../render/rendererOf.js';

export function createInteraction({ state, parts, inputFor, picking }) {
  function beginInteraction(viewer) {
    if (state._clickSubscription) return;
    state._clickSubscription = inputFor(viewer).onClick((event) => {
      if (!state._enabled) return;
      // Cable labels are not interactive, so any card or label painted on
      // top is another layer's, painted over the cable: its click.
      if (picking?.clickCard?.(event)) return;
      const record = resolvePickRecord(event.drawHit);
      if (!record?.reference) return;
      flyToReference(viewer, record.reference);
    });
  }

  /**
   * What a click's draw hit names: a cable, landing point or reference of
   * this layer's current items, as `{ label, kind, featureId, reference }`,
   * or null.
   */
  function resolvePickRecord(hit) {
    return parts.rendering.pickInfo(hit);
  }

  function flyToReference(viewer, reference) {
    if (!viewer || !reference) return;
    const camera = cameraOf(viewer);
    camera.cancelFlight();
    camera.flyTo(
      { lon: reference.lon, lat: reference.lat, height: 6500 },
      {
        orientation: {
          heading: camera.pose().heading || 0,
          pitch: toRadians(-52),
          roll: 0,
        },
        durationS: 1.35,
        easing: 'cubicInOut',
      },
    );
  }
  return {
    beginInteraction,
    resolvePickRecord,
    flyToReference,
  };
}

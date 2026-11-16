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

import { createRailLayer } from '../../layers/rail/index.js';
import * as render from '../../renderGovernor.js';
import { fleetModelServices } from './fleetModels.js';
import * as sprites from '../../data/spriteOrder.js';
import * as picking from '../../data/pickRegistry.js';
import * as overlays from '../../overlays/worldOverlay.js';
import { WORLD_FOCUS_FRAMING, requestWorldFocus } from '../../worldFocus.js';
import {
  railFeedCredit,
  registerDynamicCredit,
} from '../../data/dataCredits.js';

/**
 * Construct the Rail layer on the application's scene owners and its shared
 * ground floor, the same floor Transit and the aircraft stand on.
 * `displayParams` reads the Flights layer's DISPLAY-rail 3D preference, under
 * which nearby trains are drawn as fleet models.
 * `placement` is a host-supplied placement for its live trains, or null.
 * @param {{surface: object, source?: object, placement?: object|null,
 *   displayParams?: () => object|null, resolveAsset?: (url: string) => string}} options
 * @returns {object}
 */
export function createApplicationRail({
  surface,
  source,
  placement = null,
  displayParams = null,
  resolveAsset,
}) {
  if (!surface?.groundFloor)
    throw new TypeError('Rail needs the application surface services');
  const { groundFloor } = surface;
  return createRailLayer({
    source,
    services: {
      render,
      sprites,
      picking,
      overlays,
      placement,
      credits: { registerDynamicCredit, railFeedCredit },
      ground: {
        GROUND_FLOOR_LIFT_M: groundFloor.GROUND_FLOOR_LIFT_M,
        cachedGroundFloor: groundFloor.cachedGroundFloor,
        warmGroundFloor: groundFloor.warmGroundFloor,
        neighborFloorM: groundFloor.neighborFloorM,
        coarseFloorCoord: groundFloor.coarseFloorCoord,
      },
      // A selected train is followed as a tracked aircraft is, or flown to
      // once as a vessel is (src/layers/rail/follow.js).
      camera: {
        framing: WORLD_FOCUS_FRAMING.train,
        requestWorldFocus,
        isCockpitActive: () =>
          globalThis.document?.body?.classList?.contains('cockpit-mode') ===
          true,
      },
      fleet: fleetModelServices({
        display: displayParams,
        ...(resolveAsset ? { resolveAsset } : {}),
      }),
    },
  });
}

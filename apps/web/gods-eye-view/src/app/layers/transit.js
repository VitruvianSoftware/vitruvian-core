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

import { createTransitLayer } from '../../layers/transit/index.js';
import * as render from '../../renderGovernor.js';
import * as sprites from '../../data/spriteOrder.js';
import * as picking from '../../data/pickRegistry.js';
import * as overlays from '../../overlays/worldOverlay.js';
import {
  registerDynamicCredit,
  transitFeedCredit,
} from '../../data/dataCredits.js';

/**
 * Construct one layer using the application scene owners and the
 * application's surface services.
 *
 * The floor comes from `surface.groundFloor` — the ONE instance aircraft,
 * trails, fires and camera geometry stand on — and the rendered-mesh sampler
 * from `surface.meshFloor`, so a mesh floor the application resolves for a
 * cell is the floor transit draws on, and a transit-only session warms its
 * own mesh floors. An earlier cut imported the legacy module-level singleton
 * instead and could not see either.
 *
 * @param {{surface: object}} options
 * @returns {object}
 */
export function createApplicationTransit({ surface, source }) {
  if (!surface?.groundFloor || !surface?.meshFloor)
    throw new TypeError('Transit needs the application surface services');
  const { groundFloor, meshFloor } = surface;
  return createTransitLayer({
    source,
    services: {
      render,
      sprites,
      picking,
      overlays,
      credits: { registerDynamicCredit, transitFeedCredit },
      ground: {
        GROUND_FLOOR_LIFT_M: groundFloor.GROUND_FLOOR_LIFT_M,
        cachedGroundFloor: groundFloor.cachedGroundFloor,
        coarseFloorCoord: groundFloor.coarseFloorCoord,
        neighborFloorM: groundFloor.neighborFloorM,
        warmGroundFloor: groundFloor.warmGroundFloor,
        corridorFloorCells: groundFloor.corridorFloorCells,
        allocateCorridorCells: groundFloor.allocateCorridorCells,
      },
      mesh: { sampleMeshFloorCells: meshFloor.sampleMeshFloorCells },
    },
  });
}

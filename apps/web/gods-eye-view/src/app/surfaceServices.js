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

import { createTerrainHeights } from '../services/terrainHeights.js';
import { createGroundFloor } from '../services/groundFloor.js';
import { createMeshFloorSampler } from '../services/meshFloorSampler.js';
import { createGroundSnap } from '../services/groundSnap.js';
import { createFireAnchors } from '../layers/firms/anchors.js';

/** Own the DEM, coarse floors and mesh samples used by one application. */
export function createSurfaceServices({
  terrainSource,
  signal,
  eventTarget = globalThis.window,
}) {
  const terrain = createTerrainHeights({ source: terrainSource, signal });
  const groundFloor = createGroundFloor({ terrain, signal });
  const meshFloor = createMeshFloorSampler({
    groundFloor,
    signal,
    eventTarget,
  });
  return Object.freeze({
    terrain,
    groundFloor,
    meshFloor,
    groundSnap: Object.freeze({
      createGroundSnap: () => createGroundSnap({ groundFloor }),
    }),
    anchors: createFireAnchors(groundFloor),
    controlServices: Object.freeze({
      cachedGroundFloor: groundFloor.cachedGroundFloor,
      cachedMeshFloor: groundFloor.cachedMeshFloor,
      GROUND_FLOOR_LIFT_M: groundFloor.GROUND_FLOOR_LIFT_M,
      meshFloorPreferred: groundFloor.meshFloorPreferred,
      warmGroundFloor: groundFloor.warmGroundFloor,
      sampleMeshFloorCells: meshFloor.sampleMeshFloorCells,
    }),
  });
}

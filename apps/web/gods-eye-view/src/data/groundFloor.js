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

import { createGroundFloor } from '../services/groundFloor.js';
import * as terrain from './terrainHeights.js';
const groundFloor = createGroundFloor({ terrain });
export const {
  GROUND_FLOOR_LIFT_M,
  MESH_FLOOR_BELOW_PRIOR_M,
  MESH_FLOOR_ABOVE_PRIOR_M,
  coarseFloorCoord,
  floorAltitudeM,
  displayFloorHeightM,
  FLOOR_CELL_DEG,
  NEIGHBOR_FLOOR_MIN_SAMPLES,
  neighborFloorM,
  CORRIDOR_MAX_CELLS,
  CORRIDOR_WALK_STEP_DEG,
  CELL_HYSTERESIS_DEG,
  stickyFloorCell,
  corridorFloorCells,
  allocateCorridorCells,
  setMeshFloorPreferred,
  meshFloorPreferred,
  reportMeshFloorCell,
  meshFloorSampleWithinPrior,
  reportValidatedMeshFloorCell,
  cachedMeshFloor,
  _clearMeshFloorCellsForTest,
  cachedGroundFloor,
  FLOOR_RESOLVE_DEADLINE_MS,
  resolveGroundFloorCellsBounded,
  resolveGroundFloorCells,
  warmGroundFloor,
} = groundFloor;

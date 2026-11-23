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
 * Fleet contacts as the Flights and Vessels layers draw them: the procedural
 * fleet model set and its loader, which model and size an aircraft or a
 * vessel draws with, the icon-to-model handover distances, how a model is
 * lit, tinted and turned, the moving parts it is posed with, and the vessel
 * hull sprites. Every name here is the layers' own; nothing is redefined.
 *
 * Portable: no engine, DOM or layer state.
 */

export {
  FLEET_MODEL_BASE,
  aircraftModelSpec,
  fleetModelSet,
  fleetModelSetLoading,
  fleetModelSpec,
  fleetPartTable,
  loadFleetModelSet,
  resolveAircraft,
  resolveTransit,
  resolveVessel,
  transitModelSpec,
  vesselModelSpec,
} from '../data/fleetModels.js';
export {
  UNLOADED_AIRCRAFT_MODEL_SPEC,
  aircraftLayerModelSpec,
  aircraftModelSpecCacheKey,
} from '../layers/flights/modelSpec.js';
export {
  EMERGENCY_TINT,
  FLEET_MODEL_POLICY,
  MODEL_ADD_M,
  MODEL_ALT_CEIL_M,
  MODEL_HEADING_OFFSET_DEG,
  MODEL_KEEP_M,
  MODEL_MAX,
  MODEL_MAX_ALL,
  MODEL_WHITE,
} from '../layers/flights/policy.js';
export {
  AIRCRAFT_ENVIRONMENT_MAP_OPTIONS,
  AIRCRAFT_MODEL_TINT_MIX,
  aircraftModelBlend,
} from '../data/aircraftModelLighting.js';
export {
  aircraftLayerPartState,
  aircraftPartState,
  groundVehiclePartState,
  vesselPartState,
} from '../data/modelPartDrivers.js';
export { selectModelEligible } from '../data/modelEligibility.js';
export {
  FLEET_HEADING_OFFSET_DEG,
  fleetAxisScale,
  fleetColor,
} from '../data/fleetModelDraw.js';
export {
  VESSEL_SPRITE_PX,
  aidSprite,
  vesselSprite,
} from '../data/vesselSprites.js';
export {
  VESSEL_KINDS,
  VESSEL_KIND_STYLES,
  isAidToNavigation,
  normalizeVesselType,
  vesselKind,
} from '../data/vesselTypes.js';

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
 * Tools that answer questions from God's Eye View data, independent of the
 * surface that exposes them. See docs/TOOLS.md.
 */

import {
  aircraftInArea,
  findAircraft,
  getAircraftInfo,
  getAircraftTrack,
} from './queries/aviation.js';
import { getWeatherMap, getWind } from './queries/atmosphere.js';
import { findSubmarineCables } from './queries/cables.js';
import {
  getHudCaption,
  militaryAwareness,
  situationBrief,
} from './queries/brief.js';
import {
  findMilitaryInstallations,
  getCyclones,
  getFirePerimeters,
  getMapFeatures,
  getRegionalBrief,
  getTerrainHeight,
  getWeather,
} from './queries/environment.js';
import { getBhoteKoshiFlood } from './queries/events.js';
import { getActiveFires, getEarthquakes } from './queries/hazards.js';
import { getRecentImagery } from './queries/imagery.js';
import { findInfrastructure } from './queries/infrastructure.js';
import {
  findVessel,
  getVesselTrack,
  vesselsInArea,
} from './queries/maritime.js';
import {
  getBikeShare,
  getTrafficFlow,
  getTransitVehicles,
} from './queries/mobility.js';
import { placesNearby, planRoute, searchPlaces } from './queries/places.js';
import { panelRequest } from './queries/panelRequest.js';
import { showInGodsEyeView } from './queries/share.js';
import { findAlprCameras } from './queries/surveillance.js';
import {
  findCctvCameras,
  findRadioStations,
  getCctvSnapshot,
} from './queries/media.js';
import {
  getRecentLaunches,
  nextSatellitePass,
  satellitesOverhead,
} from './queries/space.js';

export {
  defineTool,
  composeCatalog,
  ToolError,
  TOOL_ERROR_CODES,
} from './catalog.js';
export {
  AREA_SCHEMA,
  resolveArea,
  areaCenter,
  areaContains,
  distanceKm,
} from './area.js';
export { LIMIT_SCHEMA, DEFAULT_LIMIT, MAX_LIMIT, capRows } from './results.js';
export { toFunctionOutput, toFunctionTools } from './functions.js';
export {
  SURFACES,
  TOOL_SURFACES,
  catalogForSurface,
  toolsForSurface,
} from './surfaces.js';
export {
  createGeocodePlaceService,
  createPlaceSearchService,
  createRouteService,
  placeFromGeocodeResult,
} from './places.js';

/** Every query Core defines, in a stable order. */
export const coreTools = Object.freeze([
  getEarthquakes,
  getActiveFires,
  getRecentLaunches,
  aircraftInArea,
  findAircraft,
  getAircraftTrack,
  getAircraftInfo,
  vesselsInArea,
  findVessel,
  getVesselTrack,
  nextSatellitePass,
  satellitesOverhead,
  findCctvCameras,
  getCctvSnapshot,
  findAlprCameras,
  findRadioStations,
  searchPlaces,
  placesNearby,
  planRoute,
  getBikeShare,
  getTransitVehicles,
  getTrafficFlow,
  getWeather,
  getWeatherMap,
  getWind,
  getRecentImagery,
  findSubmarineCables,
  findInfrastructure,
  getBhoteKoshiFlood,
  getRegionalBrief,
  getCyclones,
  getFirePerimeters,
  getTerrainHeight,
  findMilitaryInstallations,
  getMapFeatures,
  situationBrief,
  militaryAwareness,
  getHudCaption,
  showInGodsEyeView,
  panelRequest,
]);

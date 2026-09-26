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

export function createState({ services }) {
  const { setOverlayEntries, setOverlaySourceVisible, clearOverlaySource } =
    services.overlays;
  const layerState = {};

  layerState.DEFAULT_OVERLAY_HOST = Object.freeze({
    setEntries: setOverlayEntries,
    setVisible: setOverlaySourceVisible,
    clearSource: clearOverlaySource,
  });

  layerState._overlayHost = layerState.DEFAULT_OVERLAY_HOST;

  // ---------------------------------------------------------------------------
  // Module-level mutable state
  // ---------------------------------------------------------------------------

  /** @type {Cesium.Viewer|null} Active Cesium viewer instance. */

  layerState._viewer = null;

  /** @type {Cesium.PointPrimitiveCollection|null} Primitive collection for station dots. */

  layerState._pointCollection = null;

  /** Whether the bikeshare layer is currently enabled. */

  layerState._enabled = false;

  /** Timer handle for camera-move debounce. */

  layerState._cameraDebounceTimer = null;

  /** Whether the camera.changed listener is currently attached. */

  layerState._cameraChangedAttached = false;

  /** Hysteresis flag for altitude-based activation. */

  layerState._altitudeGateEnabled = false;

  /** Monotonic generation counter; incremented on each proximity check to cancel stale work. */

  layerState._proximityGeneration = 0;

  /** @type {Set<string>} City ids currently considered in-range. */

  layerState._activeCityIds = new Set();

  /** @type {Map<string, { stationKeys: Set<string> }>} Per-city runtime tracking of rendered station keys. */

  layerState._cityRuntime = new Map();

  /** @type {Map<string, Map<string, Object>>} Cached station information per city (cityId -> stationId -> StationInfo). */

  layerState._stationInfoCache = new Map();

  /** @type {Map<string, { timestamp: number, statusMap: Map<string, Object> }>} Cached station status per city. */

  layerState._statusCache = new Map();

  /** @type {Map<string, { promise: Promise, controller: AbortController, generation: number }>} In-flight station info requests. */

  layerState._inFlightInfo = new Map();

  /** @type {Map<string, { promise: Promise, controller: AbortController, generation: number }>} In-flight station status requests. */

  layerState._inFlightStatus = new Map();

  /** @type {Map<string, Object>} Render records keyed by "cityId:stationId". */

  layerState._stationRenderMap = new Map();

  /** @type {Cesium.ScreenSpaceEventHandler|null} Click handler for station selection. */

  layerState._clickHandler = null;

  /** @type {string|null} Key of the currently selected station, or null. */

  layerState._selectedKey = null;

  /** @type {Cesium.Entity|null} Entity used to display the selected-station point highlight. */

  layerState._selectedEntity = null;

  /** Total number of currently rendered station points. */

  layerState._count = 0;

  /** Timestamp (ms) of the last successful status update. */

  layerState._lastUpdate = null;

  /** Whether any GBFS fetch is currently in progress. */

  layerState._loading = false;

  /** Reference count of concurrent loading operations. */

  layerState._loadingOps = 0;

  /** Most recent error message string, or null. */

  layerState._error = null;

  /** Whether the MAX_TOTAL_POINTS cap warning has already been logged. */

  layerState._limitWarned = false;
  return layerState;
}

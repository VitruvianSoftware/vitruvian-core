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

import * as Cesium from 'cesium';
import { REQUEST_DEBOUNCE_MS } from './policy.js';
import { installationAnchorBox } from './source.js';

export function createViewport({ state: layerState, services, parts, source }) {
  /**
   * The area this load describes: the window around a Contacts subject while
   * one is set (a follow or Cockpit camera never settles and often looks at the
   * horizon), otherwise the settled camera viewport.
   * @param {object} viewer Cesium viewer.
   * @returns {{box: object|null, coverage: object}} Query box and its coverage.
   */
  function loadArea(viewer) {
    const anchor = layerState.contextAnchor;
    if (anchor) {
      const box = installationAnchorBox(anchor);
      if (box) {
        const { radiusM, ...bounds } = box;
        return { box: bounds, coverage: { kind: 'subject', radiusM } };
      }
    }
    return { box: viewportBox(viewer), coverage: { kind: 'viewport' } };
  }

  function viewportBox(viewer) {
    const rectangle = viewer?.camera?.computeViewRectangle(
      viewer.scene.globe.ellipsoid,
    );
    if (!rectangle) return null;
    const south = Cesium.Math.toDegrees(rectangle.south);
    const north = Cesium.Math.toDegrees(rectangle.north);
    const west = Cesium.Math.toDegrees(rectangle.west);
    const east = Cesium.Math.toDegrees(rectangle.east);
    // Wide and dateline views use the bundled point index.
    if (
      !Number.isFinite(south + north + west + east) ||
      east === west ||
      north <= south
    )
      return null;
    return { south, west, north, east };
  }

  /**
   * Backoff progression for the unavailable-state retry: 30 s, doubling to a
   * 240 s ceiling. Pure so the progression is pinnable without booting the layer.
   */

  function installationRetryDelayMs(prevDelayMs) {
    const RETRY_MIN_MS = 30000;
    const RETRY_CEIL_MS = 240000;
    if (!Number.isFinite(prevDelayMs) || prevDelayMs <= 0) return RETRY_MIN_MS;
    return Math.min(prevDelayMs * 2, RETRY_CEIL_MS);
  }

  /**
   * 'Temporarily unavailable' must mean temporarily: fetches otherwise fire only
   * on enable and on camera moveEnd, so a parked camera whose first request died
   * (one flaky Overpass mirror is enough) stayed unavailable forever while the
   * proxy sat healthy while the layer refused to show its features. While the
   * layer is enabled and
   * unavailable, retry on a 30 s → 240 s backoff; any success, user-driven load,
   * zoom-out, or disable cancels it.
   */

  function scheduleUnavailableRetry(retryAfterMs = 0) {
    if (!layerState.enabled) return;
    clearTimeout(layerState.retryTimer);
    layerState.retryDelayMs = Math.max(
      retryAfterMs,
      installationRetryDelayMs(layerState.retryDelayMs),
    );
    layerState.retryAt = Date.now() + layerState.retryDelayMs;
    layerState.retryTimer = setTimeout(() => {
      layerState.retryTimer = null;
      layerState.retryAt = 0;
      if (layerState.enabled && !layerState.loading)
        parts.ingestion.loadInstallations();
    }, layerState.retryDelayMs);
  }

  function clearUnavailableRetry({ resetBackoff = true } = {}) {
    clearTimeout(layerState.retryTimer);
    layerState.retryTimer = null;
    layerState.retryAt = 0;
    if (resetBackoff) layerState.retryDelayMs = 0;
  }

  function scheduleLoad() {
    if (!layerState.enabled) return;
    const { box, coverage } = loadArea(layerState.viewer);
    const camera = layerState.viewer.camera;
    const widePose =
      coverage.kind === 'viewport' &&
      box &&
      (box.east < box.west ||
        box.east - box.west > 10 ||
        box.north - box.south > 10)
        ? [camera.positionWC, camera.directionWC]
            .map((v) =>
              v ? [v.x, v.y, v.z].map((n) => n.toFixed(4)).join(',') : '',
            )
            .join(':')
        : '';
    const key = `${coverage.kind}:${box ? [box.south, box.west, box.north, box.east].map((v) => v.toFixed(6)).join(',') : 'wide'}:${widePose}`;
    if (layerState.cameraLoadKey === key && !layerState.error) return;
    layerState.cameraLoadKey = key;
    layerState.cameraLoadOwner = {};
    layerState.abort?.abort();
    // A user-driven load supersedes any pending retry; the load reschedules on
    // failure, so the backoff step is kept rather than reset.
    clearUnavailableRetry({ resetBackoff: false });
    clearTimeout(layerState.timer);
    layerState.timer = setTimeout(() => {
      layerState.timer = null;
      parts.ingestion.loadInstallations();
    }, REQUEST_DEBOUNCE_MS);
  }
  return {
    loadArea,
    viewportBox,
    installationRetryDelayMs,
    scheduleUnavailableRetry,
    clearUnavailableRetry,
    scheduleLoad,
  };
}

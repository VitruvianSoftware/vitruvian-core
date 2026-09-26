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
import { installationFeedback } from '../../data/installationFeedback.js';
import { LAYER_ID, DISTANCE_PREFILTER_MARGIN_M } from './policy.js';

export function createControls({ state: layerState, services, parts, source }) {
  const methods = {
    id: LAYER_ID,

    name: 'Mapped Installations',

    icon: '⌖',

    source: 'OpenStreetMap + optional Google Maps Places',

    updateInterval: 0,

    statsRefreshInterval: 1000,

    /** Request a one-shot Google Maps Places search around the current map view. */
    searchNearby() {
      layerState.googleSearchRequested = true;
      return parts.ingestion.loadInstallations();
    },

    getNearby(center, rangeM, maxCount = 50) {
      if (!center) return [];
      const range = Number.isFinite(rangeM) ? rangeM : Infinity;
      const centerCartographic = Cesium.Cartographic.fromCartesian(center);
      if (!centerCartographic) return [];
      const nearby = [];
      const approximateLimit = Number.isFinite(range)
        ? range * 1.03 + DISTANCE_PREFILTER_MARGIN_M
        : Infinity;
      for (const record of layerState.records) {
        if (record.kind !== 'installation') continue;
        if (
          parts.model.approximateSurfaceDistanceM(
            centerCartographic.latitude,
            centerCartographic.longitude,
            record.latitude,
            record.longitude,
          ) > approximateLimit
        )
          continue;
        // The awareness disk is projected onto the ground. Confirm candidates
        // with an exact ellipsoidal surface distance and reusable scratch state.
        layerState.distanceEndpointScratch.longitude = Cesium.Math.toRadians(
          record.longitude,
        );
        layerState.distanceEndpointScratch.latitude = Cesium.Math.toRadians(
          record.latitude,
        );
        layerState.distanceEndpointScratch.height = 0;
        layerState.distanceGeodesicScratch.setEndPoints(
          centerCartographic,
          layerState.distanceEndpointScratch,
        );
        const distanceM = layerState.distanceGeodesicScratch.surfaceDistance;
        if (!Number.isFinite(distanceM) || distanceM > range) continue;
        nearby.push({
          ...record,
          position: Cesium.Cartesian3.fromDegrees(
            record.longitude,
            record.latitude,
            parts.rendering.installationSurfaceHeightM(record),
          ),
          distanceM,
        });
      }
      nearby.sort((a, b) => a.distanceM - b.distanceM);
      return nearby.slice(
        0,
        Number.isFinite(maxCount) ? Math.max(1, Math.floor(maxCount)) : 50,
      );
    },

    /**
     * Select and frame a mapped installation from another contextual UI.
     * @param {string} id Source-backed installation id.
     * @returns {boolean} True when an available installation was focused.
     */
    focusById(id) {
      const record = layerState.recordById.get(String(id));
      if (!record || !layerState.viewer) return false;
      // No camera flight without a real selection: a flight plus a stale subject
      // reads as success to Context navigation and strands NEXT on this item.
      if (!parts.selection.selectRecord(record.id)) return false;
      layerState.viewer.camera.flyToBoundingSphere(
        new Cesium.BoundingSphere(
          Cesium.Cartesian3.fromDegrees(
            record.longitude,
            record.latitude,
            parts.rendering.installationSurfaceHeightM(record),
          ),
          18000,
        ),
        { duration: 1.4 },
      );
      return true;
    },

    getStats() {
      return {
        count: layerState.records.length,
        lastUpdate: layerState.lastUpdate,
        stale: layerState.stale,
        saturated: layerState.saturated,
        error: layerState.error,
        status: layerState.status,
        loading: layerState.loading,
        retryAt: layerState.retryAt,
        retrying: layerState.loading && Boolean(layerState.failureReason),
        failureReason: layerState.failureReason,
        statusMessage: installationFeedback({
          ...layerState,
          retrying: layerState.loading && Boolean(layerState.failureReason),
        }),
        loadingLabel: layerState.loading
          ? 'loading mapped installation context'
          : '',
      };
    },
  };

  return { methods };
}

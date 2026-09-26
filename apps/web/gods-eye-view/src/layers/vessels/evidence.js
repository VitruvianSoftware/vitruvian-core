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
import { FOCUS_EVIDENCE_DEV } from './policy.js';

export function createEvidence({
  vesselState,
  services,
  parts: components,
  layer,
  options,
}) {
  const { state } = vesselState;

  /** Replace live AIS rows through the production reconciliation path (DEV only). */

  function _setFocusEvidenceVessels(rows = []) {
    if (!FOCUS_EVIDENCE_DEV || !state.viewer || !state.billboardCollection) {
      return { ok: false, count: 0 };
    }
    components.selection.clearVesselInspection();
    components.snapshots.reconcileVessels(
      state.viewer,
      Array.isArray(rows) ? rows : [],
    );
    state.feed.count = state.records.all.length;
    state.feed.loaded = true;
    state.feed.error = null;
    state.feed.stale = false;
    state.feed.partial = false;
    state.feed.lastUpdate = Date.now();
    state.feed.transportStatus = 'synthetic';
    state.feed.lastMessageAt = null;
    state.feed.rawRowCount = Array.isArray(rows) ? rows.length : 0;
    state.feed.acceptedRowCount = state.feed.count;
    return { ok: true, count: state.feed.count };
  }

  /** JSON-safe vessel alpha/position snapshot for the evidence report. */

  function _focusEvidenceVesselSnapshot() {
    if (!FOCUS_EVIDENCE_DEV || !state.viewer) return [];
    return state.records.all.map((record) => {
      const bb = components.rendering.getVisual(record).billboard;
      const screen = bb?.position
        ? Cesium.SceneTransforms.worldToWindowCoordinates(
            state.viewer.scene,
            bb.position,
          )
        : null;
      return {
        id: record.mmsi,
        show: bb?.show === true,
        alpha: bb?.color?.alpha ?? null,
        x: screen?.x ?? null,
        y: screen?.y ?? null,
      };
    });
  }
  return { _setFocusEvidenceVessels, _focusEvidenceVesselSnapshot };
}

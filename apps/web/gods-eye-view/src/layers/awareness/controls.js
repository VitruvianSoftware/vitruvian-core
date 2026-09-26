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

import { AWARENESS_RADIUS_M } from '../../data/militaryAwarenessEngine.js';

export function createControls({ state: layerState, services, parts, source }) {
  const flightsLayer = services.flights;
  const militaryFlightsLayer = services.military;
  const aisLiveVesselsLayer = services.vessels;

  const methods = {
    id: 'military-awareness',

    name: 'Global Context',

    icon: '◎',

    source: 'Open-source proximity context',

    // Context is entered from its dedicated right rail, not as a raw layer.
    showInTogglePanel: false,

    updateInterval: 0,

    statsRefreshInterval: 1000,

    attachDataManager(dataManager) {
      layerState.dataManager = dataManager;
    },

    setParams(params = {}) {
      if (typeof params.passive !== 'boolean') return;
      const wasPassive = layerState.passive;
      layerState.passive = params.passive;
      if (layerState.enabled && wasPassive && !layerState.passive)
        parts.dependencies.activateOperationalContext();
    },

    /** @returns {{ passive: boolean }} Current runtime parameters. */
    getParams() {
      return { passive: layerState.passive };
    },

    getStats() {
      return {
        count: layerState.results ? 1 : 0,
        lastUpdate: layerState.results?.evaluatedAt || null,
        stale: false,
        error: null,
        status: layerState.enabled ? 'ready' : 'idle',
      };
    },

    /** Return the latest read-only context result for compact HUD consumers. */
    getContextSnapshot() {
      if (!layerState.enabled || !layerState.subject) return null;
      if (!layerState.results) {
        return parts.model.buildAwarenessContextSnapshot(
          {
            subject: { ...layerState.subject },
            evaluatedAt: null,
            radiusM: AWARENESS_RADIUS_M,
            cohorts: [],
          },
          parts.model.navigationState(),
          {
            subjectPresent: !layerState.subjectMissing,
          },
        );
      }
      return parts.model.buildAwarenessContextSnapshot(
        layerState.results,
        parts.model.navigationState(),
        {
          subjectPresent: !layerState.subjectMissing,
        },
      );
    },

    /**
     * Release Contact-owned camera tracking without discarding the selected
     * subject. Reset-to-globe uses this route so the normal Context FOCUS action
     * can explicitly return to the same contact, while delayed activation work
     * cannot silently reclaim the camera after the reset.
     * @returns {boolean} Whether a Contact subject remains selected.
     */
    releaseCameraOwnership({
      preserveVesselSelection = false,
      origin = 'programmatic',
    } = {}) {
      ++layerState.activationId;
      layerState.autoFocusAttempted = true;
      layerState.autoFocusRetryPending = false;

      const preservedSelectionKey =
        parts.subject.subjectKey(layerState.subject) || 'camera-release';
      layerState.pendingSelectionKey = preservedSelectionKey;
      try {
        flightsLayer.stopTracking?.({ origin });
        militaryFlightsLayer.stopTracking?.({ origin });
        if (!preserveVesselSelection) aisLiveVesselsLayer.clearSelection?.();
      } finally {
        if (layerState.pendingSelectionKey === preservedSelectionKey) {
          layerState.pendingSelectionKey = null;
        }
      }
      return Boolean(layerState.subject);
    },

    navigatePrevious(options = {}) {
      return parts.history.navigateHistory(-1, options);
    },

    focusCurrent(options = {}) {
      return parts.focus.focusCurrentSubject(options);
    },

    navigateNext(options = {}) {
      return parts.history.navigateHistory(1, options);
    },

    /** Select a context target through its owning layer's established tracker. */
    focusTarget(layerId, id, options = {}) {
      return parts.focus.requestFocus(layerId, id, false, options);
    },
  };

  return { methods };
}

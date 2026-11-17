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

import { cameraOf } from '../../render/rendererOf.js';
import { CAMERA_CHANGED_THRESHOLD, LAYER_ID } from './policy.js';

export function createLifecycle({
  state: layerState,
  services,
  parts,
  source,
}) {
  const { registerPickOwner, unregisterPickOwner } = services.picking;
  const { clearSelectedEntityContextForLayer } = services.context;

  const methods = {
    init(viewer) {
      layerState.viewer = viewer;
      parts.rendering.attach(viewer);
      const cameraChanged = () => {
        if (!layerState.contextAnchor) parts.viewport.scheduleLoad();
      };
      const camera = cameraOf(viewer);
      layerState.moveEndRemove = camera.on('moveEnd', cameraChanged);
      // Measured for this listener alone; off, a load is never scheduled.
      layerState.changedRemove = camera.on('changed', cameraChanged, {
        threshold: CAMERA_CHANGED_THRESHOLD,
      });
      parts.selection.installInteraction(viewer);
    },

    enable() {
      layerState.enabled = true;
      layerState.surfaceChangedRemove ||= services.maps?.subscribeMapStack(
        parts.rendering.syncSelectionFill,
      );
      // Cached markers and geometry become visible before the next fetch.
      if (
        layerState.records?.some((r) =>
          r.sources?.some((s) => s.name === 'OpenStreetMap'),
        )
      )
        services.credits?.showOsmCredit?.(layerState.viewer, LAYER_ID, {
          openMapTiles: layerState.records.some((r) =>
            r.sources?.some(
              (s) => s.name === 'OpenStreetMap' && s.id?.startsWith('tile:'),
            ),
          ),
        });
      parts.namedMarkers?.enable();
      parts.namedMarkers?.sync(layerState.records || []);
      registerPickOwner(LAYER_ID, (id) => layerState.recordById.has(id));
      parts.rendering.setShown(true);
      // DataLayerManager invokes update() immediately after enable(), which owns
      // the first fetch. Avoid racing it with a second aborting request here.
    },

    disable() {
      layerState.enabled = false;
      services.credits?.hideOsmCredit?.(layerState.viewer, LAYER_ID);
      parts.namedMarkers?.hide();
      layerState.contextAnchor = null;
      layerState.contextPosition = null;
      layerState.coverage = { kind: 'viewport' };
      layerState.cameraLoadKey = null;
      layerState.cameraLoadOwner = null;
      unregisterPickOwner(LAYER_ID);
      parts.viewport.clearUnavailableRetry();
      clearTimeout(layerState.timer);
      layerState.abort?.abort();
      layerState.abort = null;
      layerState.loading = false;
      parts.rendering.setShown(false);
      clearSelectedEntityContextForLayer(LAYER_ID);
      layerState.selectedId = null;
      parts.rendering.clearSelectionFill?.();
      layerState.surfaceChangedRemove?.();
      layerState.surfaceChangedRemove = null;
      layerState.failureReason = null;
      parts.ingestion.setInstallationStatus('idle');
    },

    destroy(viewer) {
      source.destroy?.();
      this.disable();
      layerState.contextAnchor = null;
      layerState.contextPosition = null;
      layerState.coverage = { kind: 'viewport' };
      layerState.moveEndRemove?.();
      layerState.changedRemove?.();
      parts.selection.destroy?.();
      layerState.clickSubscription?.();
      layerState.clickSubscription = null;
      parts.namedMarkers?.destroy();
      parts.rendering.clearRendered();
      parts.rendering.detach(viewer);
    },
  };

  return { methods };
}

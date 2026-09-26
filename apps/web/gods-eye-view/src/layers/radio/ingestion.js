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

import {
  RADIO_DIRECTORY_STALE_MS,
  RADIO_DIRECTORY_FUTURE_SKEW_MS,
} from './policy.js';

export function createIngestion({
  state: layerState,
  services,
  parts,
  source,
}) {
  const methods = {
    /** Refresh directory metadata through the hardened same-origin broker. */
    async update() {
      if (!layerState._enabled) return;
      const generation = ++layerState._requestGeneration;
      const sessionGeneration = layerState._sessionGeneration;
      layerState._abortController?.abort();
      layerState._abortController = new AbortController();
      layerState._loading = true;
      layerState._error = null;
      parts.presentation.emitState();
      try {
        const body = await source.getDirectory({
          signal: layerState._abortController.signal,
        });
        if (
          !parts.model.radioRequestIsCurrent(
            generation,
            layerState._requestGeneration,
            layerState._enabled,
            sessionGeneration,
            layerState._sessionGeneration,
          )
        )
          return;
        if (!Array.isArray(body?.stations))
          throw new Error('Radio directory response was malformed');
        const updatedAt =
          typeof body.updatedAt === 'string' &&
          Number.isFinite(Date.parse(body.updatedAt))
            ? body.updatedAt
            : null;
        const updatedAtMs = updatedAt ? Date.parse(updatedAt) : NaN;
        if (
          !updatedAt ||
          updatedAtMs < Date.now() - RADIO_DIRECTORY_STALE_MS ||
          updatedAtMs > Date.now() + RADIO_DIRECTORY_FUTURE_SKEW_MS ||
          typeof body.stale !== 'boolean' ||
          typeof body.degraded !== 'boolean'
        )
          throw new Error('Radio directory freshness metadata was malformed');
        const rows = body.stations;
        const acceptedRows = rows.filter(
          parts.catalogModel.isValidRadioDirectoryStation,
        );
        if (!acceptedRows.length)
          throw new Error('Radio directory returned no usable stations');
        if (acceptedRows.length !== rows.length) {
          throw new Error(
            'Radio directory response contained malformed stations',
          );
        }
        const acceptedGeneration = body.acceptedGeneration;
        if (
          acceptedGeneration !== null &&
          (!Number.isSafeInteger(acceptedGeneration) || acceptedGeneration < 1)
        )
          throw new Error('Radio directory generation metadata was malformed');
        if (!body.stale && !body.degraded && acceptedGeneration === null) {
          throw new Error('Radio directory omitted its accepted generation');
        }
        const catalogInstance = body.catalogInstance;
        if (
          !body.stale &&
          !body.degraded &&
          (typeof catalogInstance !== 'string' || !catalogInstance)
        ) {
          throw new Error('Radio directory omitted its catalog instance');
        }
        const preservingWarmCatalog =
          layerState._stations.length > 0 && (body.stale || body.degraded);
        // Generations are only comparable within one producer instance. A new
        // instance token (server restart, different proxy process) starts a fresh
        // sequence: never a repeat and never a regression.
        const sameCatalogInstance =
          layerState._acceptedCatalogSnapshot?.instance === catalogInstance;
        const currentAcceptedGeneration = sameCatalogInstance
          ? layerState._acceptedCatalogSnapshot?.generation
          : null;
        if (
          !body.stale &&
          !body.degraded &&
          Number.isSafeInteger(currentAcceptedGeneration) &&
          acceptedGeneration < currentAcceptedGeneration
        )
          throw new Error('Radio directory generation regressed');
        const repeatingAcceptedGeneration =
          !body.stale &&
          !body.degraded &&
          Number.isSafeInteger(currentAcceptedGeneration) &&
          acceptedGeneration === currentAcceptedGeneration;
        if (!preservingWarmCatalog) {
          const immutableRows = acceptedRows.map(
            parts.catalogModel.freezeRadioStation,
          );
          if (repeatingAcceptedGeneration) {
            layerState._updatedAt =
              layerState._acceptedCatalogSnapshot.updatedAt;
            if (
              !layerState._tuningActive &&
              layerState._cancelledTuningPresentationStation
            ) {
              layerState._cancelledTuningPresentationStation = null;
              parts.rendering.updateSelectionEntity();
            }
          } else if (!body.stale && !body.degraded) {
            const acceptedSnapshot =
              parts.catalogModel.createAcceptedCatalogSnapshot(
                catalogInstance,
                acceptedGeneration,
                updatedAt,
                immutableRows,
              );
            if (!acceptedSnapshot)
              throw new Error(
                'Radio directory generation metadata was malformed',
              );
            layerState._acceptedCatalogSnapshot = acceptedSnapshot;
            parts.rendering.reconcileStations(acceptedSnapshot.stations);
          } else {
            parts.rendering.reconcileStations(immutableRows);
          }
          if (!repeatingAcceptedGeneration) layerState._updatedAt = updatedAt;
        }
        layerState._degraded = body.degraded;
        layerState._stale = body.stale;
        layerState._error = preservingWarmCatalog
          ? 'Directory refresh degraded; showing the previous station catalog.'
          : layerState._degraded
            ? 'Radio directory coverage is degraded.'
            : null;
      } catch (error) {
        if (
          error?.name === 'AbortError' ||
          !parts.model.radioRequestIsCurrent(
            generation,
            layerState._requestGeneration,
            layerState._enabled,
            sessionGeneration,
            layerState._sessionGeneration,
          )
        )
          return;
        layerState._error = layerState._stations.length
          ? 'Directory refresh failed; showing the previous station catalog.'
          : 'Radio directory is temporarily unavailable.';
        layerState._stale = layerState._stations.length > 0;
        layerState._degraded = layerState._stations.length > 0;
      } finally {
        if (
          generation === layerState._requestGeneration &&
          sessionGeneration === layerState._sessionGeneration
        ) {
          layerState._loading = false;
          layerState._abortController = null;
          parts.presentation.emitState();
        }
      }
    },
  };

  return { methods };
}

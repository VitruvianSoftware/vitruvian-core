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

import { createVesselState } from './state.js';
import { createLifecycle } from './lifecycle.js';
import { createIngestion } from './ingestion.js';
import { createVesselSnapshotRenderer } from './snapshotRenderer.js';
import { createRendering } from './rendering.js';
import { createSelection } from './selection.js';
import { createTracking } from './tracking.js';
import { createCards } from './cards.js';
import { createTesting } from './testing.js';
import { createEvidence } from './evidence.js';
import { createQueries } from './queries.js';
/** Compose one vessel layer with application-owned scene services. */
export function createVesselLayer({ source, services, options = {} } = {}) {
  const vesselState = createVesselState({ source, services });
  const parts = {};
  const layer = {};
  const context = { vesselState, services, parts, layer, options };
  parts.lifecycle = createLifecycle(context);
  parts.rendering = createRendering(context);
  parts.selection = createSelection(context);
  parts.tracking = createTracking(context);
  parts.cards = createCards(context);
  parts.testing = createTesting(context);
  parts.evidence = createEvidence(context);
  parts.queries = createQueries(context);
  parts.snapshots = createVesselSnapshotRenderer({
    state: vesselState.state,
    records: vesselState.state.records,
    rendering: parts.rendering,
    tracking: parts.tracking,
    selection: parts.selection,
    cards: parts.cards,
  });

  parts.ingestion = createIngestion({
    feed: vesselState.state.feed,
    readSource: () => vesselState._source,
    readViewer: () => vesselState.state.viewer,
    getRowLimit: parts.rendering.renderRowLimit,
    readCount: () => vesselState.state.records.all.length,
    applyRows: parts.snapshots.reconcileVessels,
    classifySnapshot: parts.queries.classifyAisFeedSnapshot,
    isDefinitiveTransportFailure: parts.lifecycle.isDefinitiveTransportFailure,
    isGraceEligibleTransport: parts.lifecycle.isGraceEligibleTransport,
    markUnavailable: parts.lifecycle.markAisUnavailable,
    settleFirstConnect: parts.lifecycle.settleFirstConnectPhase,
    now: () => vesselState._aisRuntime.now(),
    setSourceLabel: (source) => {
      layer.source = source;
    },
  });
  Object.assign(
    layer,
    parts.queries.methods,
    parts.lifecycle.methods,
    parts.ingestion.methods,
  );
  layer.source = source?.label || 'Vessels';
  Object.assign(layer, {
    applyVesselFocusDeemphasis: parts.rendering.applyVesselFocusDeemphasis,
    buildVesselCard: parts.cards.buildVesselCard,
    buildSelectedVesselCard: parts.cards.buildSelectedVesselCard,
    cardScreenSeparated: parts.cards.cardScreenSeparated,
  });
  Object.defineProperty(layer, 'testing', { value: parts.testing });
  return layer;
}
export { AIS_FIRST_CONNECT_GRACE_MS } from './policy.js';
export {
  VESSEL_OVERLAY_SOURCE_ID,
  VESSEL_LABEL_GRID_PX,
  VESSEL_DEFAULT_LABEL_LIMIT,
  VESSEL_OVERLAY_MAX_COHORT,
  VESSEL_CARD_FADE_DISTANCE_M,
  normalizeVesselType,
  vesselTypeCss,
  accentForVesselType,
  vesselOverlayCohortLimit,
  applyVesselOverlayPolicy,
} from '../../data/vesselLabels.js';

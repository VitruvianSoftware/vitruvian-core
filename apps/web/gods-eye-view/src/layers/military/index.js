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

import { createMilitarySnapshotRenderer } from './snapshotRenderer.js';
import { createFlightState } from './state.js';
import { createRendering } from './rendering.js';
import { createIcons } from './icons.js';
import { createMotion } from './motion.js';
import { createTracking } from './tracking.js';
import { createController } from './controller.js';
import { createIngestion } from './ingestion.js';
import { createLifecycle } from './lifecycle.js';
import { createTesting } from './testing.js';
import { createQueries } from './queries.js';
import { createClockFollow } from './clockFollow.js';
import {
  createSnapshotTimeline,
  snapshotAnswer,
} from '../../time/snapshotTimeline.js';
import { worldClock } from '../../time/worldClock.js';
/** Compose one military-flight layer with application-owned scene services. */
export function createMilitaryFlightLayer({
  source,
  services,
  resolveAsset = (url) => url,
} = {}) {
  const flightState = createFlightState({ source, services });
  const parts = {};
  const layer = {};
  const context = { flightState, services, parts, layer, resolveAsset };
  parts.rendering = createRendering(context);
  parts.icons = createIcons(context);
  parts.motion = createMotion(context);
  parts.tracking = createTracking(context);
  parts.controller = createController(context);
  parts.lifecycle = createLifecycle(context);
  parts.testing = createTesting(context);
  parts.queries = createQueries(context);
  parts.clockFollow = createClockFollow(context);
  const applySnapshot = createMilitarySnapshotRenderer({
    flightState,
    placement: services.placement ?? null,
    records: flightState.records,
    groundFloor: services.groundFloor,
    militaryRegistry: services.militaryRegistry,
    rendering: parts.rendering,
    tracking: parts.tracking,
    motion: parts.motion,
    icons: parts.icons,
    queries: parts.queries,
  });
  parts.ingestion = createIngestion({
    feed: flightState.feed,
    applySnapshot: (snapshot, viewer, options) => {
      // At another time the snapshot takes the place of every contact: how
      // each moved belongs to the time the clock left. Back at live too, but
      // the contacts it lacks are kept as they were for it to judge.
      if (options?.replace) parts.clockFollow.resetMotion();
      if (options?.handover) {
        parts.clockFollow.handOverMotion(
          parts.clockFollow.absentAtHandover(snapshot),
        );
      }
      return applySnapshot(snapshot, viewer, options);
    },
    followsClock: () => flightState.timeline.active(),
    timedAnswer: snapshotAnswer,
    setSourceLabel: (source) => {
      layer.source = source;
    },
    applyPendingTrackingRestore: () =>
      parts.tracking._applyPendingTrackingRestore(),
  });

  // Contacts follow the world clock while the source declares a timeline.
  flightState.timeline = createSnapshotTimeline({
    id: 'military',
    clock: worldClock,
    source: () => flightState.feed._source,
    load: (atMs, { signal, replace }) =>
      parts.ingestion.methods.loadAt(atMs, { signal, replace }),
    clear: () => parts.clockFollow.clear(),
    resumeLive: () => parts.ingestion.methods.resumeLive(flightState._viewer),
  });

  Object.assign(
    layer,
    parts.queries.methods,
    parts.lifecycle.methods,
    parts.ingestion.methods,
  );
  Object.defineProperty(layer, 'testing', { value: parts.testing });
  return layer;
}

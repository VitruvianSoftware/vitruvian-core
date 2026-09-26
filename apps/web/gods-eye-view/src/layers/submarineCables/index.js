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

import { createState } from './state.js';
import { createLifecycle } from './lifecycle.js';
import { defaultSweepClock } from './policy.js';
import { createRendering } from './rendering.js';
import { createIngestion } from './ingestion.js';
import { createInteraction } from './interaction.js';
export function createSubmarineCableLayer({
  source,
  overlayHost,
  screenSpaceEventHandlerFactory,
  mapStackEventTarget = null,
  sweepClock = defaultSweepClock,
}) {
  if (!source?.fetch || !source.label)
    throw new TypeError(
      'A cable source with a label and fetch(signal) is required',
    );
  const state = createState({ overlayHost, sweepClock });
  const parts = {};
  const context = {
    state,
    parts,
    source,
    screenSpaceEventHandlerFactory,
    mapStackEventTarget,
  };
  parts.rendering = createRendering(context);
  parts.ingestion = createIngestion(context);
  parts.interaction = createInteraction(context);
  return createLifecycle(context);
}
export {
  selectCableReferenceLabelWinners,
  cableReferencePriority,
  createCableOverlayEntry,
  createCableOverlayPublisher,
  createCableReferenceSweepGate,
  updateCableReferenceStem,
} from './overlay.js';
export {
  cableClassificationTypeForStack,
  cableClassificationTypeForScene,
  applyTranslucentMarkerBlend,
} from './surface.js';
export {
  CABLE_REFERENCE_LABEL_WINNER_CAP,
  CABLE_OVERLAY_SOURCE_ID,
  CABLE_OVERLAY_COLLISION_CAPACITY,
  CABLE_STEM_TIP_EPSILON_M,
  CABLE_SWEEP_MOTION_PROBE_INTERVAL_MS,
  CABLE_SWEEP_MOTION_EPSILON_M,
  CABLE_LABEL_DEPTH_DECISION,
} from './policy.js';

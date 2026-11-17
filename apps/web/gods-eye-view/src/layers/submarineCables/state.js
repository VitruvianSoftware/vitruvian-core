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
  createCableReferenceSweepGate,
  createCableOverlayPublisher,
} from './overlay.js';
import { BASE_CABLE_COLOR, BASE_LANDING_COLOR } from './policy.js';

export function createState({ sweepClock, overlayHost }) {
  const state = {};

  state._viewer = null;

  state._enabled = false;

  state._loading = false;

  state._loaded = false;

  state._count = 0;

  state._error = null;

  state._lastUpdate = null;

  state._loadingLabel = '';

  state._abort = null;

  /** Monotonic load-ownership token; every load() start claims a new one. */

  state._loadGeneration = 0;

  /**
   * The layer's draw sets, made at init: cable and landing lines (draped),
   * pins (landing points), fills (polygons), stems and reference points.
   */

  state._sets = null;

  /** Set ids this layer made, for matching picks. */

  state._setIds = new Set();

  /** What each drawn item is, by set id then item id (picks fly to it). */

  state._picks = new Map();

  /** Drawn surface items, culled by their feature's reference each sweep. */

  state._surfaceItems = [];

  /**
   * Fetched cable/landing JSON kept across disable/enable. A disable CLEARS
   * the draw sets (see releaseDrawing) instead of hiding them, so a
   * re-enable has to rebuild the items; the network/parse half of that
   * rebuild is the expensive part users would notice, so it is cached.
   */

  state._cachedCableJson = null;

  state._cachedLandingJson = null;

  state._referenceRecords = [];

  state._clickSubscription = null;

  state._preRenderRemover = null;

  state._moveEndRemover = null;

  state._mapStackListener = null;

  /** What ground lines drape on; refined from live scene state at init. */

  state._clampTo = 'both';

  state._referenceLabelCount = 0;

  state._referenceSweepGate = createCableReferenceSweepGate({
    now: sweepClock,
  });

  state._overlayPublisher = createCableOverlayPublisher({ host: overlayHost });

  /** Reused winner→entry scratch so a 2 Hz sweep allocates no arrays. */

  state._publishScratch = [];

  /**
   * Last published cohort signature (ids + quantized priorities). A parked
   * camera reproduces the same winners every sweep; skipping the identical
   * republish keeps the host from requesting a render per publish, so the
   * layer stays render-governor idle exactly like its native predecessor.
   * Tip positions need no republish either: the host reprojects the same
   * mutable Cartesians on every painted frame.
   */

  state._lastPublishedIds = [];

  state._lastPublishedPriorities = [];

  state._lastPublishedCount = -1;

  state.cableColor = BASE_CABLE_COLOR;

  state.landingColor = BASE_LANDING_COLOR;
  return state;
}

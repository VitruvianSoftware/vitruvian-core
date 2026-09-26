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

export function createState({ services }) {
  const state = {};

  state.DIRECTION_SCRATCH = Array.from(
    { length: 3 },
    () => new Cesium.Cartesian3(),
  );

  state.SUBJECT_CARTOGRAPHIC_SCRATCH = new Cesium.Cartographic();

  state.TARGET_CARTOGRAPHIC_SCRATCH = Array.from(
    { length: 3 },
    () => new Cesium.Cartographic(),
  );

  Object.assign(state, {
    viewer: null,
    dataManager: null,
    enabled: false,
    // Set once a refresh observes the subject gone from a still-reporting source.
    // The Contact readout turns this into its CONTACT LOST hold state.
    subjectMissing: false,
    // The dedicated Context chooser exposes a passive shell. Operational source
    // layers activate only after Contacts is explicitly selected.
    passive: true,
    ownedDependencies: new Set(),
    subject: null,
    results: null,
    visual: null,
    panel: null,
    panelOwned: false,
    subjectListener: null,
    contextListener: null,
    clearListener: null,
    subjectClearListener: null,
    runtimeListenersAttached: false,
    preRenderRemover: null,
    panelClickListener: null,
    directionRoot: null,
    compassRing: null,
    compassLabels: [],
    compassHeading: null,
    directionMarkers: [],
    navigationHistory: [],
    navigationVisited: new Set(),
    navigationIndex: -1,
    suppressedHistoryKey: null,
    pendingSelectionKey: null,
    lastSubjectRefreshMs: 0,
    /** Camera-pose signature observed on the previous rendered frame. */
    lastCameraPoseSig: '',
    /** When the pose signature last changed bins (hysteresis anchor). */
    lastCameraPoseChangeMs: 0,
    /** Whether the view currently counts as moving (hysteretic, not per-frame). */
    cameraMoving: false,
    lastEvaluatedPosition: null,
    sourceRevision: '',
    panelMarkup: '',
    directionFrame: null,
    lastDirectionUpdateMs: 0,
    activationId: 0,
    autoFocusAttempted: false,
    autoFocusRetryPending: false,
    pageTimer: null,
    cohortPages: new Map(),
  });
  return state;
}

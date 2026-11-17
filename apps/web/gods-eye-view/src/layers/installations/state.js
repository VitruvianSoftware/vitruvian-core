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

export function createState({ services }) {
  const state = {};

  Object.assign(state, {
    viewer: null,
    /** The layer's draw sets (`dots`, `outlines`, `fills`) while attached. */
    sets: null,
    enabled: false,
    records: [],
    recordById: new Map(),
    selectedId: null,
    lastUpdate: null,
    error: null,
    status: 'idle',
    stale: false,
    /** Whether the upstream truncated at its element cap for the current view. */
    saturated: false,
    loading: false,
    abort: null,
    /** Pending timed retry while status is 'unavailable' (see scheduleUnavailableRetry). */
    retryTimer: null,
    /** Current backoff step for that retry; 0 = next failure starts at the minimum. */
    retryDelayMs: 0,
    retryAt: 0,
    failureReason: null,
    moveEndRemove: null,
    clickSubscription: null,
    timer: null,
    googleSearchRequested: false,
    /** Contacts subject position; when set, it replaces the camera viewport. */
    contextAnchor: null,
    /** Latest subject centre, independent of the retained tile-fetch anchor. */
    contextPosition: null,
    /** Coverage of the last successful load: viewport, or radius around a subject. */
    coverage: { kind: 'viewport' },
    /**
     * What each drawn record last drew: its geometry key, outline item ids,
     * context carrier, height and selection, for in-place updates.
     */
    renderedKeys: new Map(),
  });
  return state;
}

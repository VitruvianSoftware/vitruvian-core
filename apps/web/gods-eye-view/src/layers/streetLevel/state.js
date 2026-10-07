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

import { FILTER_DEFAULT } from './policy.js';

/**
 * The per-image fields of `state.street` with no image open; closing resets
 * exactly these (host, render mode and follow availability outlive an image).
 */
export function freshStreet() {
  return {
    open: false,
    follow: false,
    providerId: null,
    providerName: null,
    providerLabel: null,
    imageId: null,
    position: null,
    bearing: null,
    tilt: null,
    altitude: null,
    isPano: false,
    capturedAt: null,
    sequenceId: null,
    creator: null,
    externalUrl: null,
    loading: false,
    error: null,
  };
}

/** Mutable core state, created once per layer instance. */
export function createState({ services }) {
  return {
    services,
    viewer: null,
    enabled: false,
    initialized: false,
    destroyed: false,
    listeners: new Set(),
    notify: null,
    /** Shared imagery filter, in the stored (relative-days) form. */
    filter: { ...FILTER_DEFAULT },
    /** @type {Map<string, {def: object, instance: object, on: boolean}>} */
    providers: new Map(),

    street: {
      host: null,
      /** Whether the active map stack allows following (Google 3D only). */
      followAvailable: false,
      /** 'letterbox' shows the whole image; 'fill' crops it to the frame. */
      renderMode: 'letterbox',
      ...freshStreet(),
    },

    /** 'terrain' on Google 3D at street zoom (overlays on the bare earth), else 'draped'. */
    surface: 'draped',

    marker: { collection: null, billboard: null },
    clickHandler: null,
  };
}

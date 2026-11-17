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

/**
 * @module render/cesium/viewers
 * @description The Cesium viewer behind each renderer the application's
 * plugin made (`appRenderer.js`), and the viewer behind a scene object the app
 * holds: the one its bound renderer draws with, or the scene object itself
 * when it is a viewer with no renderer bound.
 */
import { rendererOf } from '../rendererOf.js';

const viewers = new WeakMap();

/**
 * Record `viewer` as the one behind `renderer`.
 * @param {object} renderer
 * @param {object} viewer
 */
export function recordViewer(renderer, viewer) {
  viewers.set(renderer, viewer);
}

/**
 * The Cesium viewer behind a renderer the application's plugin made, or
 * null for the test stub.
 * @param {object} renderer
 * @returns {object|null}
 */
export const cesiumViewerOf = (renderer) =>
  (renderer && viewers.get(renderer)) || null;

/**
 * The Cesium viewer behind the scene object `host`: its bound renderer's,
 * else `host` itself (a viewer with no renderer bound, or none at all).
 * @param {object|null|undefined} host
 * @returns {object|null|undefined}
 */
export const viewerBehind = (host) => cesiumViewerOf(rendererOf(host)) ?? host;

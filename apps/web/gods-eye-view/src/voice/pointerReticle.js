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
 * A subtle reticle at the point "this" resolved to, shown while the turn is
 * live so the user sees what was understood before the answer.
 *
 * It is a fixed-position overlay (pointer-events: none) placed from the
 * snapshot's canvas pixels, so it never touches the Cesium scene. It is
 * presented to the pointer reticle store, which the command dock renders.
 * The reticle marks where the user pointed, not a tracked world position: it
 * leaves as soon as a tool moves the camera, when the reply completes, when
 * the session ends, and after {@link RETICLE_MAX_MS} at most. Clean-UI and
 * recording mode hide it through CSS.
 */

import { usePointerReticleStore } from '../ui/stores/pointerReticle.js';
import { applicationPinia } from '../ui/vueRuntime.js';

export const RETICLE_MAX_MS = 10000;
export const RETICLE_LINGER_MS = 1500;

/** Tools that move the camera away from the pointed spot. */
const CAMERA_TOOLS = new Set([
  'fly_to_location',
  'track_entity',
  'zoom_to_globe',
  'adjust_camera_zoom',
  'move_camera',
  'fly_route',
  'frame_overhead',
  'select_nearest_aircraft',
  'control_cockpit',
]);

// Keys each reticle's element in the view.
let reticleKeys = 0;

export class PointerReticle {
  /**
   * @param {object} options
   * @param {() => {left: number, top: number}|null} options.rectOf Canvas
   *   client rect, read at show time.
   * @param {object} [options.store] The pointer reticle store.
   * @param {Function} [options.setTimer]
   * @param {Function} [options.clearTimer]
   */
  constructor({
    rectOf,
    store = usePointerReticleStore(applicationPinia()),
    setTimer = (fn, ms) => setTimeout(fn, ms),
    clearTimer = (id) => clearTimeout(id),
  }) {
    Object.assign(this, { rectOf, store, setTimer, clearTimer });
    this.key = ++reticleKeys;
    // What this reticle last presented; null until it first shows.
    this.view = null;
    this.timer = null;
    // Tools running in this turn, keyed by call id (name when absent).
    this.running = new Set();
    this.visible = false;
    this.destroyed = false;
  }

  schedule(ms) {
    this.cancelTimer();
    this.timer = this.setTimer(() => {
      this.timer = null;
      this.hide();
    }, ms);
  }

  cancelTimer() {
    if (this.timer === null) return;
    this.clearTimer(this.timer);
    this.timer = null;
  }

  /** Show at a snapshot's canvas pixels. */
  show(pointer) {
    if (this.destroyed || !pointer?.screenPx) return;
    const rect = this.rectOf?.();
    if (!rect) return;
    this.view = {
      visible: true,
      left: Math.round(rect.left + pointer.screenPx.x),
      top: Math.round(rect.top + pointer.screenPx.y),
      target: pointer.kind === 'this' ? 'entity' : 'ground',
    };
    this.store.publish(this, this.view);
    this.visible = true;
    this.running.clear();
    this.schedule(RETICLE_MAX_MS);
  }

  hide() {
    this.cancelTimer();
    this.running.clear();
    if (!this.visible) return;
    this.visible = false;
    this.view = { ...this.view, visible: false };
    this.store.publish(this, this.view);
  }

  /** Follow provider-neutral session events. */
  handle(event) {
    if (this.destroyed || !event?.type) return;
    switch (event.type) {
      case 'pointer':
        if (event.pointer) this.show(event.pointer);
        else this.hide();
        return;
      case 'state':
        if (['idle', 'error'].includes(event.state)) this.hide();
        return;
      case 'action-call':
        if (!this.visible) return;
        if (CAMERA_TOOLS.has(event.name)) this.hide();
        else this.running.add(event.callId || event.name);
        return;
      case 'action-result':
        this.running.delete(event.callId || event.name);
        return;
      case 'completion':
        if (this.visible && this.running.size === 0)
          this.schedule(RETICLE_LINGER_MS);
        return;
      default:
    }
  }

  destroy() {
    if (this.destroyed) return;
    this.hide();
    this.destroyed = true;
    if (this.view) this.store.publish(this, null);
    this.view = null;
  }
}

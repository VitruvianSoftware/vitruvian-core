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

/** Own deferred UI presentation and listeners until synchronous teardown. */
export class UiLifetime {
  constructor() {
    this.destroyed = false;
    this.removers = new Set();
    this.frames = new Set();
    this.timers = new Set();
  }
  listen(target, type, callback, options) {
    if (this.destroyed || !target) return () => {};
    const remove = () => {
      target.removeEventListener(type, listener, options);
      this.removers.delete(remove);
    };
    const listener = (event) => {
      if (options?.once) remove();
      if (!this.destroyed) return callback(event);
    };
    target.addEventListener(type, listener, options);
    this.removers.add(remove);
    return remove;
  }
  frame(callback) {
    if (this.destroyed) return null;
    const frame = requestAnimationFrame((time) => {
      this.frames.delete(frame);
      if (!this.destroyed) callback(time);
    });
    this.frames.add(frame);
    return frame;
  }
  timeout(callback, delay) {
    if (this.destroyed) return null;
    const timer = setTimeout(() => {
      this.timers.delete(timer);
      if (!this.destroyed) callback();
    }, delay);
    this.timers.add(timer);
    return timer;
  }
  cancelTimeout(timer) {
    clearTimeout(timer);
    this.timers.delete(timer);
  }
  destroy() {
    if (this.destroyed) return;
    this.destroyed = true;
    for (const remove of this.removers) remove();
    for (const frame of this.frames) cancelAnimationFrame(frame);
    for (const timer of this.timers) clearTimeout(timer);
    this.frames.clear();
    this.timers.clear();
  }
}

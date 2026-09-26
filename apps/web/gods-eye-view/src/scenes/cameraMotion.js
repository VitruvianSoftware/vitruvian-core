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

import { sampleCameraMove } from '../director/camera.js';

/** Own one authored camera animation and settle it immediately on cancellation or replacement. */
export function createCameraMotion({
  applyPose,
  now = () => performance.now(),
  requestFrame = (callback) => requestAnimationFrame(callback),
  cancelFrame = (handle) => cancelAnimationFrame(handle),
} = {}) {
  let active = null;
  let disposed = false;
  const cancel = () => active?.finish(false);
  return {
    get active() {
      return active !== null;
    },
    cancel,
    destroy() {
      disposed = true;
      cancel();
    },
    play(move, token) {
      cancel();
      if (disposed || token?.cancelled || token?.signal?.aborted)
        return Promise.resolve(false);
      if (!Number.isFinite(move.durationSec) || move.durationSec <= 0)
        throw new RangeError('Camera move duration must be positive');
      return new Promise((resolve, reject) => {
        const run = { handle: null, finish: null };
        const startedAt = now();
        const onAbort = () => run.finish(false);
        run.finish = (completed, error) => {
          if (active !== run) return;
          active = null;
          if (run.handle !== null) cancelFrame(run.handle);
          token?.signal?.removeEventListener('abort', onAbort);
          if (error) reject(error);
          else resolve(completed);
        };
        active = run;
        token?.signal?.addEventListener('abort', onAbort, { once: true });
        const tick = () => {
          if (active !== run) return;
          run.handle = null;
          if (disposed || token?.cancelled || token?.signal?.aborted) {
            run.finish(false);
            return;
          }
          try {
            const progress = Math.min(
              1,
              Math.max(0, (now() - startedAt) / (move.durationSec * 1000)),
            );
            if (applyPose(sampleCameraMove(move, progress)) === false) {
              run.finish(false);
              return;
            }
            // Applying a pose can synchronously transfer camera ownership.
            if (active !== run) return;
            if (progress >= 1) run.finish(true);
            else run.handle = requestFrame(tick);
          } catch (error) {
            run.finish(false, error);
          }
        };
        tick();
      });
    },
  };
}

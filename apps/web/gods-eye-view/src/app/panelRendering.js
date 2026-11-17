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
 * @module app/panelRendering
 * @description Keeping the globe drawing in an inline panel whose host stops
 * animation frames (`src/app/embed.js`, embed mode), through the ports alone: the
 * application scene hands it to the embed views (`src/app/scene.js`).
 */

// A panel keeps drawing at about this rate when its host stops animation
// frames; see keepPanelRendering.
const PANEL_FRAME_MS = 33;
const MISSED_FRAMES_MS = 250;

/** A render error's details, including the plain objects workers report. */
function describeError(error) {
  if (error instanceof Error)
    return `${error.name}: ${error.message}\n${error.stack}`;
  try {
    return JSON.stringify(error, Object.getOwnPropertyNames(error ?? {}));
  } catch {
    return String(error);
  }
}

/**
 * Keep `renderer` drawing in an inline panel. Some hosts report a panel on
 * screen as hidden, which stops the browser's animation frames and with them
 * the renderer's own loop; while frames stop arriving, draw from a timer
 * (`resize`, then a frame of the loop, `frame.renderNow({ifDue: true})`: the
 * camera moves, input and the clock run, and it draws when due). While the
 * renderer's loop is stopped after a failed frame (`stopped` in its frame
 * diagnostics) the timer waits, and goes on once a retry starts the loop
 * again; the render failure notice reports the error
 * (src/render/cesium/renderFailure.js). Where the renderer never says so, a frame
 * that fails stops the timer, its error reported in full. Returns a
 * function that stops it.
 * @param {import('../render/contract/renderer').Renderer} renderer
 * @param {{windowRef?: Window, now?: () => number}} [options]
 * @returns {() => void}
 */
export function keepPanelRendering(
  renderer,
  { windowRef = globalThis.window, now = () => performance.now() } = {},
) {
  let lastFrame = now();
  let frameRequest = null;
  const onFrame = () => {
    lastFrame = now();
    frameRequest = windowRef.requestAnimationFrame(onFrame);
  };
  frameRequest = windowRef.requestAnimationFrame(onFrame);
  let failed = false;
  const stopped = () => renderer.frame.diagnostics?.().stopped;
  const timer = windowRef.setInterval(() => {
    if (failed || now() - lastFrame < MISSED_FRAMES_MS || stopped()) return;
    try {
      renderer.resize();
      renderer.frame.renderNow({ ifDue: true });
    } catch (error) {
      // Stopped by now: the render failure notice has the error.
      if (stopped() !== undefined) return;
      // Report the error in full: workers report plain objects, which
      // would print as [object Object].
      failed = true;
      console.error(
        "[God's Eye View panel] render error:",
        describeError(error),
      );
    }
  }, PANEL_FRAME_MS);
  return () => {
    windowRef.clearInterval(timer);
    windowRef.cancelAnimationFrame(frameRequest);
  };
}

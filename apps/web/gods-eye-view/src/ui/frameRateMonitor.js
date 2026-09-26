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

/** Count rendered globe frames while the optional readout is visible. */
export function createFrameRateMonitor({ viewer, documentRef = document }) {
  const host = documentRef.getElementById('title-bar');
  const frameEvent = viewer?.scene?.postRender;
  if (!host || !frameEvent) return { destroy() {} };

  const readout = documentRef.createElement('div');
  readout.className = 'frame-rate-readout';
  readout.hidden = true;
  readout.textContent = 'FPS —';
  readout.title = 'Rendered globe frames per second · toggle with `';
  host.appendChild(readout);
  let removeFrameListener = null;
  let timer = null;
  let frames = 0;
  let startedAt = 0;
  let destroyed = false;

  function hide() {
    readout.hidden = true;
    removeFrameListener?.();
    removeFrameListener = null;
    clearInterval(timer);
    timer = null;
  }

  function show() {
    frames = 0;
    startedAt = performance.now();
    readout.textContent = 'FPS —';
    readout.hidden = false;
    removeFrameListener = frameEvent.addEventListener(() => {
      frames++;
    });
    timer = setInterval(() => {
      const now = performance.now();
      const elapsed = now - startedAt;
      readout.textContent =
        documentRef.hidden || elapsed <= 0
          ? 'FPS —'
          : `FPS ${Math.round((frames * 1000) / elapsed)}`;
      frames = 0;
      startedAt = now;
    }, 1000);
  }

  function onKeyDown(event) {
    if (event.key !== '`' && event.code !== 'Backquote') return;
    if (
      event.defaultPrevented ||
      event.repeat ||
      event.isComposing ||
      event.ctrlKey ||
      event.altKey ||
      event.metaKey ||
      event.shiftKey
    )
      return;
    if (
      event.target?.isContentEditable ||
      event.target?.closest?.(
        'input, textarea, select, [contenteditable]:not([contenteditable="false"])',
      )
    )
      return;
    event.preventDefault();
    if (readout.hidden) show();
    else hide();
  }

  documentRef.addEventListener('keydown', onKeyDown);
  return {
    destroy() {
      if (destroyed) return;
      destroyed = true;
      hide();
      documentRef.removeEventListener('keydown', onKeyDown);
      readout.remove();
    },
  };
}

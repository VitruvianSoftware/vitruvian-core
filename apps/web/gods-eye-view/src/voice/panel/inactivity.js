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

/** Local inactivity only. Unknown activity never authorizes expiry. */
export function createVoiceInactivity({
  readActivity,
  readPending,
  minutes = 5,
  onExpire,
  signal,
  setTimer = setTimeout,
  clearTimer = clearTimeout,
  now = Date.now,
}) {
  if (!Number.isInteger(minutes) || minutes < 0 || minutes > 60) minutes = 5;
  let disposed = false,
    timer = null,
    deadline = null,
    eligible = false,
    epoch = 0;
  function cancel() {
    epoch++;
    if (timer !== null) clearTimer(timer);
    timer = deadline = null;
  }
  function quiet() {
    const a = readActivity();
    return (
      a.known &&
      a.connected &&
      !a.held &&
      !a.inputBusy &&
      !a.outputBusy &&
      !a.generationBusy &&
      !readPending()
    );
  }
  function arm() {
    cancel();
    if (!minutes || disposed) return;
    const id = epoch;
    deadline = now() + minutes * 60000;
    timer = setTimer(() => {
      if (disposed || id !== epoch) return;
      timer = deadline = null;
      eligible = quiet();
      if (eligible) onExpire?.();
    }, minutes * 60000);
  }
  function update({ activity = false } = {}) {
    if (disposed) return;
    const next = quiet();
    if (!next) cancel();
    else if (!eligible || activity) arm();
    eligible = next;
  }
  function setMinutes(value) {
    if (!Number.isInteger(value) || value < 0 || value > 60) return false;
    if (disposed) return false;
    minutes = value;
    eligible = false;
    update();
    return true;
  }
  function destroy() {
    if (disposed) return;
    disposed = true;
    cancel();
    signal?.removeEventListener('abort', destroy);
  }
  signal?.addEventListener('abort', destroy, { once: true });
  if (signal?.aborted) destroy();
  update();
  return {
    update,
    setMinutes,
    snapshot: () => ({ minutes, deadline, eligible, disposed }),
    destroy,
  };
}

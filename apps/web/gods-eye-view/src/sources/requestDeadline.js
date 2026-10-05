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

/** Bound acquisition and body consumption, including transports that ignore abort. */
export async function requestWithDeadline(operation, { signal, timeoutMs }) {
  const controller = new AbortController();
  const cancel = () => controller.abort(signal.reason);
  if (signal?.aborted) cancel();
  else signal?.addEventListener('abort', cancel, { once: true });
  let rejectWait;
  const aborted = new Promise((_, reject) => {
    rejectWait = reject;
  });
  const rejectAbort = () => rejectWait(controller.signal.reason);
  controller.signal.addEventListener('abort', rejectAbort, { once: true });
  const timer = setTimeout(
    () =>
      controller.abort(new DOMException('Request timed out', 'TimeoutError')),
    timeoutMs,
  );
  try {
    controller.signal.throwIfAborted();
    return await Promise.race([operation(controller.signal), aborted]);
  } finally {
    clearTimeout(timer);
    signal?.removeEventListener('abort', cancel);
    controller.signal.removeEventListener('abort', rejectAbort);
    controller.abort();
  }
}

/** Cancel one consumer's wait without cancelling a shared acquisition. */
export async function waitForSignal(promise, signal) {
  if (!signal) return promise;
  signal.throwIfAborted();
  let cancel;
  const aborted = new Promise((_, reject) => {
    cancel = () => reject(signal.reason);
    signal.addEventListener('abort', cancel, { once: true });
  });
  try {
    return await Promise.race([promise, aborted]);
  } finally {
    signal.removeEventListener('abort', cancel);
  }
}

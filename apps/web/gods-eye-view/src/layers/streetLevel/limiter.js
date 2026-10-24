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
 * A gate letting at most `limit` tasks run at once, first in first out, or
 * newest first with `lifo` (the last request is the one the user waits on).
 */
export function createLimiter(limit, { lifo = false } = {}) {
  let running = 0;
  const queue = [];
  function next() {
    while (running < limit && queue.length) {
      const { task, resolve, reject, signal } = lifo
        ? queue.pop()
        : queue.shift();
      if (signal?.aborted) {
        reject(signal.reason);
        continue;
      }
      running++;
      Promise.resolve()
        .then(task)
        .then(resolve, reject)
        .finally(() => {
          running--;
          next();
        });
    }
  }
  return {
    run(task, { signal } = {}) {
      return new Promise((resolve, reject) => {
        const item = { task, resolve, reject, signal };
        queue.push(item);
        signal?.addEventListener(
          'abort',
          () => {
            const at = queue.indexOf(item);
            if (at === -1) return;
            queue.splice(at, 1);
            reject(signal.reason);
          },
          { once: true },
        );
        next();
      });
    },
    get pending() {
      return running + queue.length;
    },
  };
}

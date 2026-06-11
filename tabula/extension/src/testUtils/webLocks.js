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
 * Minimal Web Locks API polyfill for jsdom tests.
 *
 * Chrome extension pages and MV3 service workers always expose
 * navigator.locks; jsdom does not. Production code paths rely on the lock
 * for cross-context serialization, so tests must exercise the locked path.
 *
 * Supports: exclusive mode, FIFO ordering per name, { ifAvailable: true }.
 */

function createWebLocksMock() {
  /** name -> tail promise of the wait chain */
  const tails = new Map();
  /** name -> number of holders + waiters */
  const pending = new Map();

  return {
    async request(name, optionsOrCallback, maybeCallback) {
      const callback =
        typeof optionsOrCallback === "function"
          ? optionsOrCallback
          : maybeCallback;
      const options =
        typeof optionsOrCallback === "function" ? {} : optionsOrCallback || {};

      if (options.ifAvailable && (pending.get(name) || 0) > 0) {
        return callback(null);
      }

      pending.set(name, (pending.get(name) || 0) + 1);

      const prev = tails.get(name) || Promise.resolve();
      let release;
      const current = new Promise((resolve) => {
        release = resolve;
      });
      tails.set(
        name,
        prev.then(() => current),
      );

      await prev;
      try {
        return await callback({ name, mode: "exclusive" });
      } finally {
        pending.set(name, (pending.get(name) || 1) - 1);
        release();
      }
    },
  };
}

module.exports = { createWebLocksMock };

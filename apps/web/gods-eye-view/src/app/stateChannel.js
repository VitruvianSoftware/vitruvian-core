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

/** Copy plain product data so a subscriber cannot mutate its owner's state. */
function copyState(value, ancestors = new Set()) {
  if (value === null) return value;
  if (typeof value !== 'object') {
    if (['string', 'number', 'boolean', 'undefined'].includes(typeof value))
      return value;
    throw new TypeError('Product state must contain plain data');
  }
  if (ancestors.has(value)) throw new TypeError('Circular product state');
  if (
    !Array.isArray(value) &&
    Object.getPrototypeOf(value) !== Object.prototype &&
    Object.getPrototypeOf(value) !== null
  ) {
    throw new TypeError('Product state must contain plain records');
  }
  const next = new Set(ancestors).add(value);
  const copy = Array.isArray(value)
    ? value.map((item) => copyState(item, next))
    : Object.fromEntries(
        Object.entries(value).map(([key, item]) => [
          key,
          copyState(item, next),
        ]),
      );
  return Object.freeze(copy);
}

/**
 * Publish immutable snapshots and ordinary action outcomes synchronously.
 * Reentrant publications retain order. New subscribers start at current state;
 * removed subscribers and destroyed channels cannot receive queued work.
 */
export function createStateChannel(readSnapshot) {
  const listeners = new Set();
  const pending = [];
  let revision = 0;
  let delivering = false;
  let destroyed = false;
  let lastSnapshot = null;
  const getSnapshot = () => {
    if (!destroyed) lastSnapshot = copyState(readSnapshot());
    return lastSnapshot;
  };
  const deliver = (entry, notification) => {
    try {
      entry.listener(notification);
    } catch {
      console.error('Product state listener failed');
    }
  };
  return Object.freeze({
    getSnapshot,
    subscribe(listener, { emitCurrent = true } = {}) {
      if (typeof listener !== 'function')
        throw new TypeError('Expected a state listener');
      if (destroyed) return () => {};
      const state = emitCurrent ? getSnapshot() : null;
      const entry = { listener, revision };
      listeners.add(entry);
      if (emitCurrent)
        deliver(
          entry,
          Object.freeze({
            state,
            change: null,
            revision,
            initial: true,
          }),
        );
      return () => listeners.delete(entry);
    },
    publish(change = null) {
      if (destroyed) return false;
      pending.push(
        Object.freeze({
          state: getSnapshot(),
          change: copyState(change),
          revision: ++revision,
          initial: false,
        }),
      );
      if (delivering) return true;
      delivering = true;
      try {
        while (!destroyed && pending.length) {
          const notification = pending.shift();
          for (const entry of [...listeners]) {
            if (
              destroyed ||
              !listeners.has(entry) ||
              entry.revision >= notification.revision
            )
              continue;
            entry.revision = notification.revision;
            deliver(entry, notification);
          }
        }
      } finally {
        delivering = false;
      }
      return true;
    },
    destroy() {
      if (destroyed) return;
      destroyed = true;
      listeners.clear();
      pending.length = 0;
    },
  });
}

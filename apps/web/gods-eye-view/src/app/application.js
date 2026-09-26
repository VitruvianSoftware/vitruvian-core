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

const START_ORDER = ['scene', 'controls', 'data', 'tools'];
// Controls cancel restoration while the data manager and viewer still exist.
const STOP_ORDER = ['tools', 'controls', 'data', 'scene'];

/**
 * Own application startup and teardown without importing an application entry.
 * Constructors receive earlier components, an AbortSignal and defer(cleanup).
 * Register cleanup immediately after acquiring each resource, before any await.
 * @param {{createScene:Function,createControls:Function,createData:Function,createTools:Function}} constructors
 * @returns {{start:Function,destroy:Function,subscribe:Function,getState:Function,getComponents:Function}}
 */
export function createApplication({
  createScene,
  createControls,
  createData,
  createTools,
}) {
  const factories = {
    scene: createScene,
    controls: createControls,
    data: createData,
    tools: createTools,
  };
  for (const phase of START_ORDER) {
    if (typeof factories[phase] !== 'function')
      throw new TypeError(`Missing ${phase} constructor`);
  }
  const controller = new AbortController();
  const cleanups = Object.fromEntries(START_ORDER.map((phase) => [phase, []]));
  const components = {};
  const listeners = new Set();
  let state = Object.freeze({ status: 'created', phase: null });
  let startPromise;
  let destroyPromise;
  let cleanupPromise;

  function publish(status, phase = null) {
    state = Object.freeze({ status, phase });
    for (const listener of [...listeners]) {
      try {
        listener(state);
      } catch {
        console.error('Application state listener failed');
      }
    }
  }

  function cleanup() {
    cleanupPromise ||= Promise.resolve().then(async () => {
      const errors = [];
      for (const phase of STOP_ORDER) {
        while (cleanups[phase].length) {
          try {
            await cleanups[phase].pop()();
          } catch (error) {
            errors.push(error);
          }
        }
        delete components[phase];
      }
      if (errors.length)
        throw new AggregateError(errors, 'Application cleanup failed');
    });
    return cleanupPromise;
  }

  async function initialize() {
    try {
      for (const phase of START_ORDER) {
        controller.signal.throwIfAborted();
        publish('starting', phase);
        controller.signal.throwIfAborted();
        let acceptingCleanup = true;
        try {
          components[phase] = await factories[phase]({
            ...components,
            signal: controller.signal,
            defer(dispose) {
              if (!acceptingCleanup || typeof dispose !== 'function') {
                throw new TypeError(
                  'Register cleanup during component construction',
                );
              }
              cleanups[phase].push(dispose);
            },
          });
        } finally {
          acceptingCleanup = false;
        }
        controller.signal.throwIfAborted();
      }
      publish('ready');
      controller.signal.throwIfAborted();
      return Object.freeze({ ...components });
    } catch (error) {
      controller.abort();
      let failure = error;
      try {
        await cleanup();
      } catch (cleanupError) {
        failure = new AggregateError(
          [error, cleanupError],
          'Application startup and cleanup failed',
        );
      }
      if (!destroyPromise) publish('failed');
      throw failure;
    }
  }

  return Object.freeze({
    start() {
      if (destroyPromise)
        return Promise.reject(new Error('Application has been destroyed'));
      // Assign before notifying subscribers, including reentrant start/destroy.
      startPromise ||= Promise.resolve().then(initialize);
      return startPromise;
    },
    destroy() {
      if (destroyPromise) return destroyPromise;
      destroyPromise = Promise.resolve().then(async () => {
        try {
          await startPromise?.catch(() => {});
          await cleanup();
          publish('destroyed');
        } catch (error) {
          publish('failed');
          throw error;
        } finally {
          listeners.clear();
        }
      });
      controller.abort();
      publish('destroying');
      return destroyPromise;
    },
    getState: () => state,
    getComponents: () => Object.freeze({ ...components }),
    subscribe(listener) {
      if (typeof listener !== 'function')
        throw new TypeError('Expected a state listener');
      if (state.status === 'destroyed') return () => {};
      listeners.add(listener);
      try {
        listener(state);
      } catch {
        console.error('Application state listener failed');
      }
      return () => listeners.delete(listener);
    },
  });
}

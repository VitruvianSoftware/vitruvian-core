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

/** Bind a source contract once for the application without replacing its layer instance. */
export function createSourceSlot(
  initial,
  methods,
  label = 'Source',
  optional = {},
) {
  let active = initial;
  let binding = null;
  const source = Object.fromEntries(
    [...methods, ...Object.keys(optional)].map((method) => [
      method,
      (...args) => {
        if (typeof active?.[method] !== 'function' && optional[method])
          return optional[method](...args);
        if (typeof active?.[method] !== 'function')
          throw new Error(`${label} is not configured`);
        const owner = binding;
        const provider = active;
        const value = provider[method](...args);
        if (value && typeof value.then === 'function')
          return value.then((result) => {
            if (binding !== owner || active !== provider)
              throw new DOMException(`${label} was replaced`, 'AbortError');
            return result;
          });
        return value;
      },
    ]),
  );
  for (const property of ['label', 'attribution']) {
    Object.defineProperty(source, property, {
      enumerable: true,
      get: () => active?.[property],
    });
  }
  return {
    source,
    configure(next) {
      if (methods.some((method) => typeof next?.[method] !== 'function'))
        throw new TypeError(`Invalid ${label.toLowerCase()}`);
      const owner = Symbol(label);
      active = next;
      binding = owner;
      return () => {
        if (binding !== owner) return;
        active = null;
        binding = null;
      };
    },
  };
}

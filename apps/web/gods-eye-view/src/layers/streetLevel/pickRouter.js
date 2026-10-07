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
 * Route picked ids to the provider whose prefix they carry; the registry
 * guarantees prefixes never overlap.
 * @param {() => Iterable<{def: {id: string, pickPrefix: string}, instance: object}>} getProviders
 * @param {{positionId?: string}} [options]  Id of the core-owned position marker.
 */
export function createPickRouter(getProviders, { positionId = null } = {}) {
  function resolve(id) {
    if (typeof id !== 'string' || !id) return null;
    if (positionId && id === positionId)
      return { providerId: null, instance: null, id };
    for (const entry of getProviders())
      if (id.startsWith(entry.def.pickPrefix))
        return { providerId: entry.def.id, instance: entry.instance, id };
    return null;
  }
  return {
    ownsPick: (id) => resolve(id) !== null,
    resolve,
  };
}

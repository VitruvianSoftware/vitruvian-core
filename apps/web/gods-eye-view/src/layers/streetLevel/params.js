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

import { normalizeFilter } from './filter.js';

/**
 * Share-link params: one boolean per provider plus the filter. The codec in
 * src/data/layerState.js names the same keys, so a new provider needs one there.
 * @param {{providers: Iterable<[string, boolean]>, filter: {pano: string, sinceDays: number}}} input
 */
export function encodeParams({ providers, filter }) {
  const params = {};
  for (const [id, on] of providers) params[id] = on === true;
  params.pano = filter.pano;
  params.sinceDays = filter.sinceDays;
  return params;
}

/**
 * Read params back, ignoring unknown providers and malformed values so a link
 * from a build with more providers still applies.
 * @param {object} params
 * @param {{providerIds: Iterable<string>, filter: {pano: string, sinceDays: number}}} current
 * @returns {{providers: Map<string, boolean>, filter: {pano: string, sinceDays: number}}}
 */
export function decodeParams(params, { providerIds, filter }) {
  const providers = new Map();
  const source = params && typeof params === 'object' ? params : {};
  for (const id of providerIds)
    if (typeof source[id] === 'boolean') providers.set(id, source[id]);
  const next = {};
  if ('pano' in source) next.pano = source.pano;
  if ('sinceDays' in source) next.sinceDays = source.sinceDays;
  return { providers, filter: normalizeFilter(next, filter) };
}

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

import { COLORS } from './policy.js';

/**
 * @typedef {object} ProviderSnapshot
 * @property {string} id
 * @property {string} name
 * @property {string} label
 * @property {boolean} on
 * @property {boolean|null} configured   null until the status call answers
 * @property {boolean} keyRequired   no usable key: missing or rejected
 * @property {boolean} [keyRejected] the provider refused the configured key
 * @property {string|null} requiresKeyId
 * @property {boolean} loading
 * @property {number} count
 * @property {string} hint
 * @property {string|null} error
 * @property {string} color   The source's one colour.
 */

/**
 * Totals over switched-on providers. Key-gated only when every one lacks its
 * key; `keyRejected` when that is because a key was refused.
 * @param {Array<ProviderSnapshot>} providers
 */
export function summarizeCoverage(providers) {
  const active = providers.filter((p) => p.on);
  return {
    count: active.reduce((sum, p) => sum + (p.count || 0), 0),
    loading: active.some((p) => p.loading),
    hint: active.find((p) => p.hint)?.hint || '',
    error: active.find((p) => p.error)?.error || null,
    keyRequired:
      active.length > 0 && active.every((p) => p.keyRequired === true),
    keyRejected:
      active.length > 0 &&
      active.every((p) => p.keyRequired === true) &&
      active.some((p) => p.keyRejected === true),
  };
}

/**
 * The panel snapshot from core state and provider snapshots. The legend has
 * one swatch per active source, then the shared selection colour.
 * @param {{enabled: boolean, filter: object, providers: Array<ProviderSnapshot>, street: object, sequence: object}} input
 */
export function composeUIState({
  enabled,
  filter,
  providers,
  street,
  sequence,
  surface = 'draped',
}) {
  const active = providers.filter((p) => p.on);
  const { keyRequired, keyRejected, ...coverage } =
    summarizeCoverage(providers);
  const legend = active.map((provider) => ({
    key: provider.id,
    label: provider.name,
    color: provider.color,
  }));
  if (active.length)
    legend.push({ key: 'selected', label: 'Selected', color: COLORS.selected });
  return {
    enabled,
    keyRequired,
    keyRejected,
    filter: { ...filter },
    providers: providers.map((p) => ({ ...p })),
    coverage,
    legend,
    sequence: { ...sequence },
    street: { ...street },
    surface,
  };
}

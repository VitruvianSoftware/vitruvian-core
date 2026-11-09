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

import { t } from '../../i18n/index.js';

/** Compact card ages in translated minutes, hours or days. */
export function formatAge(deltaMs) {
  if (!Number.isFinite(deltaMs) || deltaMs < 0) return null;
  const hours = Math.floor(deltaMs / 3_600_000);
  if (hours < 1)
    return t('{count}m', {
      context: 'age',
      count: Math.max(1, Math.floor(deltaMs / 60_000)),
    });
  if (hours < 24) return t('{count}h', { context: 'age', count: hours });
  return t('{count}d', { context: 'age', count: Math.floor(hours / 24) });
}

/** Use the creator portion of the supplied attribution, never a guessed
 * observer/login. iNaturalist appends rights and licence text after it. */
export function photoCreator(photo) {
  if (typeof photo?.attribution !== 'string') return null;
  const creator = photo.attribution
    .replace(/^\s*(?:\(c\)|©|copyright)\s*/i, '')
    .replace(/,\s*(?:some|no|all)\s+rights\s+reserved\b.*$/i, '')
    .replace(
      /(?:,\s*|\s*\()(?:CC[\s-]+BY(?:[\s-]+(?:NC|SA|ND))*|CC0|public\s+domain)(?:\s+\d(?:\.\d)?)?\)?\s*$/i,
      '',
    )
    .trim();
  if (
    !creator ||
    /^(?:(?:some|no|all)\s+rights\s+reserved\b|CC(?:0|[\s-]+BY)\b)/i.test(
      creator,
    )
  )
    return null;
  return creator;
}

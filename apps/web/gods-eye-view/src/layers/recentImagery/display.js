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
 * Recent Imagery text in the page's language: days, metres and the focused
 * day's readout. The model (`model.js`) stays English and i18n-free because AI
 * tool services import it outside the browser; this module is page-only.
 */
import {
  formatDate,
  formatRelativeTime,
  getLocale,
  t,
} from '../../i18n/index.js';
import { formatQuantity } from '../../ui/unitLabels.js';
import { dayTime } from './model.js';

const SHORT_DAY = Object.freeze({
  month: 'short',
  day: 'numeric',
  timeZone: 'UTC',
});
const LONG_DAY = Object.freeze({ ...SHORT_DAY, year: 'numeric' });

/** `Sep 18` / `18 сент.` for a `YYYY-MM-DD` day, in the page's language. */
export function displayDay(day, options = SHORT_DAY) {
  const time = dayTime(day);
  return time === null ? '' : formatDate(time, options);
}

/** `30 m` / `30 м`, number and unit kept together. */
export const displayMetres = (value) => formatQuantity(value, 'm');

/** The readout's words in the page's language; the model keeps them English. */
export const READOUT_WORDS = Object.freeze({
  date: (day) => displayDay(day, LONG_DAY),
  daysAgo: (delta) => {
    const text = formatRelativeTime(delta > 0 ? -delta : 0, 'day');
    return getLocale() === 'zh-CN' ? text.replace(/(\d)(?=天)/g, '$1 ') : text;
  },
  // "Sentinel-2" never breaks at its hyphen: a word joiner follows it
  // (JetBrains Mono has no U+2011 non-breaking hyphen).
  sensor: (sensor) =>
    t(sensor).replace(/(?<=[\p{L}\p{N}])-(?=[\p{L}\p{N}])/gu, '-\u2060'),
  metres: displayMetres,
  overview: () => t('overview'),
  cloud: (cloud) => {
    if (!cloud) return t('cloud unknown');
    const min = Math.round(cloud.min);
    const max = Math.round(cloud.max);
    return min === max
      ? t('{percent}% scene cloud', { percent: min })
      : t('{min}–{max}% scene cloud', { min, max });
  },
});

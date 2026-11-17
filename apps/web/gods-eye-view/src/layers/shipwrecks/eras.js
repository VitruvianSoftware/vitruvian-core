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

/** Era chips, oldest first; a wreck with no known year sits in its own chip. */
export const SHIPWRECK_ERAS = Object.freeze([
  'before-1900',
  '1900-1945',
  'after-1945',
  'undated',
]);

/**
 * The era a wreck belongs to. Ancient wrecks dated only by period
 * ("Roman Imperial", "C1st AD") count as before 1900.
 * @param {{year?: number|null, ancient?: boolean}} record
 * @returns {string}
 */
export function eraOf(record) {
  const year = Number.isInteger(record?.year) ? record.year : null;
  if (year === null) return record?.ancient ? 'before-1900' : 'undated';
  if (year < 1900) return 'before-1900';
  if (year <= 1945) return '1900-1945';
  return 'after-1945';
}

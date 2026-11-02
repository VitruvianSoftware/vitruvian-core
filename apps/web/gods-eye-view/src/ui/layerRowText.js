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

const ROW_TEXT_SEPARATOR = ' · ';

// A short Latin code joined by hyphens: every part after a hyphen is capitals
// or digits (ADS-B, RTL-SDR, GTFS-RT). A compound such as "ALPR-Kameras" is a
// word, not a code, and may break at its hyphen. Longer runs (a URL, a token
// in an error) keep their break opportunities so they cannot overflow the rail.
const HYPHENATED_CODE = /\b[A-Za-z0-9]+(?:-[A-Z0-9]+)+(?![A-Za-z0-9])/g;
const HYPHENATED_CODE_MAX = 16;

/**
 * Split a row's name, count or meta line so that a narrow column wraps it well
 * in every language: a Latin code with hyphens (ADS-B, RTL-SDR, GTFS-RT) never
 * splits at its hyphen, and a " · " separator stays at the end of the line it
 * closes, so no line starts with "·". Each run is `{text, keep}`, where `keep`
 * stops the browser breaking inside it; the runs join back to the text. Text
 * with neither feature returns null and is shown as it is.
 *
 * @param {string} text
 * @returns {Array<{text: string, keep: boolean}>|null}
 */
export function rowTextRuns(text) {
  const value = String(text ?? '');
  const codes = [...value.matchAll(HYPHENATED_CODE)].filter(
    (match) => match[0].length <= HYPHENATED_CODE_MAX,
  );
  if (!codes.length && !value.includes(ROW_TEXT_SEPARATOR)) return null;
  const runs = [];
  const pushPlain = (from, to) => {
    if (to <= from) return;
    const pieces = value.slice(from, to).split(ROW_TEXT_SEPARATOR);
    pieces.forEach((piece, index) => {
      // The space before the dot belongs to a no-wrap run, so the only break
      // opportunity around a separator is the space after it.
      if (index > 0) runs.push({ text: ' ·', keep: true });
      const textPiece = index > 0 ? ` ${piece}` : piece;
      if (textPiece) runs.push({ text: textPiece, keep: false });
    });
  };
  let cursor = 0;
  for (const match of codes) {
    pushPlain(cursor, match.index);
    runs.push({ text: match[0], keep: true });
    cursor = match.index + match[0].length;
  }
  pushPlain(cursor, value.length);
  return runs;
}

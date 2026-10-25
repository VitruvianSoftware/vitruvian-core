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
 * Spoken-reply lint shared by the turn spans, the unit tests and the QA
 * harnesses. Pure: no browser or provider dependencies.
 */

/**
 * Phrases that add length without adding an answer. Tool numbers are spoken
 * verbatim, so approximations are hedges too.
 */
const HEDGE_PHRASES = Object.freeze([
  'keep in mind',
  "it's worth noting",
  'it is worth noting',
  'please note',
  'note that',
  'based on the data available',
  'based on the available data',
  'i should mention',
  'as of my',
  'it seems',
  'it appears',
  'approximately',
  'roughly',
  'let me think',
  'let me check',
  'one moment while',
  'bear with me',
  'just to be clear',
]);

const WORD = /[\p{L}\p{N}][\p{L}\p{N}'’-]*/gu;

/**
 * Count spoken words in a transcript.
 * @param {string} text
 * @returns {number}
 */
export function countWords(text) {
  return String(text || '').match(WORD)?.length || 0;
}

/**
 * Return every hedge phrase found in a transcript, in list order.
 * @param {string} text
 * @returns {string[]}
 */
export function findHedges(text) {
  const normalized = ` ${String(text || '')
    .toLowerCase()
    .replace(/[’]/g, "'")
    .replace(/[^\p{L}\p{N}' ]+/gu, ' ')
    .replace(/\s+/g, ' ')} `;
  return HEDGE_PHRASES.filter((phrase) => normalized.includes(` ${phrase} `));
}

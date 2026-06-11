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
 * extractLeadingEmoji
 *
 * Checks if the given string starts with an emoji (including complex ones).
 * If it does, returns the emoji and the "clean" string (minus the emoji).
 * Otherwise returns null for emoji and the original string.
 *
 * Uses a regex that attempts to capture common emoji patterns.
 * Note: Perfect emoji regex is complex; this covers most common cases including
 * surrogate pairs and variation selectors.
 */
// function signature start
export function extractLeadingEmoji(text: string): {
  emoji: string | null;
  cleanTitle: string;
} {
  if (!text) {
    return { emoji: null, cleanTitle: text };
  }

  const trimmed = text.trim();

  // Regex Explanation:
  // \p{Extended_Pictographic}: Matches most base emojis
  // (\u200D\p{Extended_Pictographic})*: Matches Zero Width Joiner sequences (e.g., family, profession)
  // [\uFE0F\uFE0E]?: Matches Variation Selectors (VS15/VS16)
  // [\u{1F3FB}-\u{1F3FF}]?: Matches Skin Tone Modifiers
  //
  // We use the 'u' flag for unicode support.
  // This is a simplified approximation but covers 99% of use cases.
  // We prioritize capturing the first grapheme cluster that looks like an emoji.

  // A more robust but still approximate regex for the *first* emoji
  const emojiRegex =
    /^(\p{Extended_Pictographic}(?:\u200D\p{Extended_Pictographic})*[\uFE0F\uFE0E]?[\u{1F3FB}-\u{1F3FF}]?)(.*)/u;

  const match = trimmed.match(emojiRegex);

  if (match) {
    // Check if the match is actually a "text" char that falls into broad categories (like digit or # or * which sometimes match)
    // However, Extended_Pictographic is pretty good.
    // Some implementation nuances:
    // Digits 0-9 can be Extended_Pictographic if followed by FE0F 20E3 (Keycap).
    // This regex might split keycaps incorrectly if not careful, but for "Workspace Names"
    // users usually paste a full emoji.

    // Let's use a simpler heuristic for now: rely on the user's intent.
    // If it matches, we take it.

    return {
      emoji: match[1],
      cleanTitle: match[2].trim(),
    };
  }

  return { emoji: null, cleanTitle: text };
}

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

/** The tags a scene saved to Stories can carry, and their limits. */

// Marks each English key for translation without loading the i18n runtime
// into the scene document validator; the panel shows them through t().
const msg = (text) => text;

/** Tag keys in display order; stored in English on `scene.storyTags`. */
export const STORY_TAGS = Object.freeze([
  msg('Floods'),
  msg('Wildfires'),
  msg('Storms'),
  msg('Earthquakes'),
  msg('Flights'),
  msg('Maritime'),
  msg('Space'),
  msg('Conflict'),
  msg('Infrastructure'),
  msg('Climate'),
]);

/** At most this many tags per scene. */
export const STORY_TAG_LIMIT = 5;

/**
 * Whether `tags` is a valid `storyTags` value: unique keys from STORY_TAGS,
 * at most STORY_TAG_LIMIT of them.
 * @param {unknown} tags
 * @returns {boolean}
 */
export function isStoryTagList(tags) {
  return (
    Array.isArray(tags) &&
    tags.length <= STORY_TAG_LIMIT &&
    new Set(tags).size === tags.length &&
    tags.every((tag) => STORY_TAGS.includes(tag))
  );
}

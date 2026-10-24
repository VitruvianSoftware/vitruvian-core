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
 * The reason for «Scene not saved — {reason}» when the project fails
 * validation. The validator's text («$.scenes[6].title: expected …») is for
 * the console: known failures get a sentence with 1-based numbers, others a
 * general one (English keeps the raw text). director.js logs the full error.
 */

import { formatNumber, getLocale, t } from '../i18n/index.js';

const TEXT_LIMIT = /^expected nonempty text, at most (\d+) characters$/;
const SCENE_TITLE = /^\$\.scenes\[(\d+)\]\.title$/;
const SHOT_TITLE = /^\$\.scenes\[(\d+)\]\.shots\[(\d+)\]\.title$/;

const ordinal = (index) => formatNumber(Number(index) + 1);

/**
 * @param {unknown} error Usually a SceneDocumentError ({path, reason}).
 * @returns {string} Reason in the UI language.
 */
export function sceneSaveFailureReason(error) {
  const path = typeof error?.path === 'string' ? error.path : '';
  const reason =
    typeof error?.reason === 'string'
      ? error.reason
      : String(error?.message || '').slice(path ? path.length + 2 : 0);
  const limit = TEXT_LIMIT.exec(reason);
  if (limit) {
    const max = formatNumber(Number(limit[1]));
    const scene = SCENE_TITLE.exec(path);
    if (scene)
      return t(
        'the title of scene {scene} is empty or longer than {max} characters',
        { scene: ordinal(scene[1]), max },
      );
    const shot = SHOT_TITLE.exec(path);
    if (shot)
      return t(
        'the title of shot {shot} in scene {scene} is empty or longer than {max} characters',
        { scene: ordinal(shot[1]), shot: ordinal(shot[2]), max },
      );
  }
  if (path === '$' && reason === 'file exceeds 5 MiB')
    return t('the project is larger than 5 MiB');
  if (reason === 'too many shots in project')
    return t('the project has too many shots');
  // English keeps the validator's own text, which names the field; another
  // language gets a general sentence (the field is in the console warning).
  if (getLocale() === 'en' && error?.message) return String(error.message);
  return t('the scene data failed validation');
}

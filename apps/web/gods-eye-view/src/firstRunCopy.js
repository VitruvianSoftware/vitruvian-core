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

// The first-run launcher's owner-chosen copy, shared by the launcher and the
// welcome view that renders it.
import { msg, t } from './i18n/index.js';

/**
 * Owner-selectable name for the fires/quakes mission. Flip this ONE constant to
 * re-label the tile; the alternates are pre-written so the choice is a taste
 * call at review time, not an edit.
 * @type {'ENVIRONMENTAL'|'EARTH_WATCH'|'ACTIVE_EVENTS'}
 */
export const ENVIRONMENTAL_LABEL_CHOICE = 'ENVIRONMENTAL';

const ENVIRONMENTAL_LABEL_KEYS = Object.freeze({
  ENVIRONMENTAL: msg('ENVIRONMENTAL'),
  EARTH_WATCH: msg('EARTH WATCH'),
  ACTIVE_EVENTS: msg('ACTIVE EVENTS'),
});

/**
 * @param {string} [choice]
 * @returns {{title: string}} The label set the constant above selects.
 */
export function environmentalLabel(choice = ENVIRONMENTAL_LABEL_CHOICE) {
  const key =
    ENVIRONMENTAL_LABEL_KEYS[choice] || ENVIRONMENTAL_LABEL_KEYS.ENVIRONMENTAL;
  return { title: t(key) };
}

/** The status line between missions. */
export const FIRST_RUN_TIP = msg(
  'Tip: the GEV MIC button in the dock lets you talk to the map.',
);

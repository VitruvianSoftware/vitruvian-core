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
 * The Cockpit Contact card's state as it first renders. It needs only the
 * i18n module, so the controller and the view can both read it.
 */
import { t } from '../i18n/index.js';

/** Cohorts the card counts, in its order. */
const COCKPIT_CONTEXT_COHORTS = Object.freeze([
  'flights',
  'military',
  'ais-live-vessels',
  'military-installations',
]);

/**
 * The card before any snapshot: navigation on, counts and readouts empty,
 * weather off. The controller keeps it, changes it in place and publishes a
 * copy; `CockpitContext` renders it.
 * @returns {object}
 */
export function createContextState() {
  return {
    state: null,
    subject: t('CONTACTS · 250 KM'),
    canPrevious: true,
    canNext: true,
    cohorts: Object.fromEntries(
      COCKPIT_CONTEXT_COHORTS.map((id) => [id, { count: '—', unknown: false }]),
    ),
    nearest: { label: t('NO AVAILABLE EXAMPLE'), ariaLabel: null },
    distance: { text: '—', ariaLabel: null },
    direction: { angle: null, unknown: false },
    bearing: '—',
    uncertainty: t('AVAILABLE INPUTS ONLY · NOT AN ALL-CLEAR'),
    updated: '--:--:--Z',
    weather: false,
  };
}

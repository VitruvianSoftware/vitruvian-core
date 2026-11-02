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

import { msg } from '../i18n/index.js';

/** Class of the element each side stack hosts its rail in. */
export const PANEL_RAIL_HOST_CLASS = 'gev-panel-rail';

/** Glyph for a panel without a catalog entry, such as one a host adds. */
export const PANEL_RAIL_FALLBACK_ICON = 'more_horiz';

/**
 * How each side panel appears on its rail. Labels are the panels' own titles.
 * `shownBy` names a class the panel needs to be shown at all (`f` toggles
 * Data Layers' `active`).
 */
export const PANEL_RAIL_ITEMS = Object.freeze({
  'data-panel': {
    icon: 'layers',
    label: msg('DATA LAYERS'),
    shownBy: 'active',
  },
  'scene-panel': { icon: 'movie', label: msg('AUTHORING') },
  'pp-toggles': { icon: 'tune', label: msg('DISPLAY') },
  'cctv-panel': { icon: 'videocam', label: msg('CCTV') },
  'weather-panel': { icon: 'partly_cloudy_day', label: msg('WEATHER') },
  'recent-imagery-panel': {
    icon: 'satellite_alt',
    label: msg('RECENT IMAGERY'),
  },
  'street-level-panel': { icon: 'streetview', label: msg('STREET LEVEL') },
  'global-context-panel': { icon: 'radar', label: msg('CONTEXT') },
});

/**
 * Whether a mutation happened inside a panel rail, which no stack layout or
 * panel state depends on.
 * @param {MutationRecord} record Observed mutation.
 */
export function isPanelRailMutation(record) {
  const target =
    record.target.nodeType === 1 ? record.target : record.target.parentElement;
  return Boolean(target?.closest?.(`.${PANEL_RAIL_HOST_CLASS}`));
}

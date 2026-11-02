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
 * The Cockpit briefing's pages and the state it starts in. It needs only the
 * i18n module, so the controller and the view can both read it.
 */
import { msg, t } from '../i18n/index.js';

export const COCKPIT_BRIEF_PAGES = [
  {
    id: 'signals',
    kickerKey: msg('LIVE SIGNALS'),
    subtitleKey: msg('OBSERVED / MAPPED PINGS'),
    sourceKey: msg('SOURCE-BACKED EVENTS · NO SYNTHETIC NEWS'),
  },
  {
    id: 'news',
    kickerKey: msg('REGIONAL NEWS'),
    subtitleKey: msg('LATEST LOCATION-MATCHED REPORTING'),
    sourceKey: msg('{source} · LOCATION QUERY · RECENT'),
    sourceName: 'GOOGLE NEWS RSS', // i18n-ignore: provider name
  },
  {
    id: 'local',
    kickerKey: msg('LOCAL INFO'),
    subtitleKey: msg('PLACE / CONDITIONS / POSITION'),
    // Attribution stays English.
    source: 'NATURAL EARTH · OPEN-METEO · UTC',
  },
];

// The cycle toggle's tooltip, as literal keys for the extractor.
export const CYCLE_HELP_KEYS = Object.freeze({
  on: msg(
    'Stop automatic page cycling. Previous, Next, and the SIG/NEWS/LOCAL tabs stay available.',
  ),
  off: msg(
    'Cycle briefing pages automatically every 9 seconds (Signals → News → Local). Pauses while you hover or focus the panel. Live signal data refreshes continuously either way.',
  ),
});

/**
 * The briefing as it first renders: the Live Signals page, cycling off, news
 * still loading and no region yet. The controller keeps it, changes it in
 * place and publishes a copy; `CockpitBriefing` renders it.
 * @returns {object}
 */
export function createBriefState() {
  const page = COCKPIT_BRIEF_PAGES[0];
  return {
    pageIndex: 0,
    pageId: page.id,
    kicker: t(page.kickerKey),
    subtitle: t(page.subtitleKey),
    position: `1 / ${COCKPIT_BRIEF_PAGES.length}`,
    source: t(page.sourceKey),
    autoRotate: false,
    autoLabel: t('CYCLE OFF'),
    autoHelp: t(CYCLE_HELP_KEYS.off),
    regionalStatus: null,
    news: {
      statusHidden: false,
      state: null,
      status: t('ACQUIRING REGIONAL NEWS'),
      articles: [],
    },
    local: {
      place: t('RESOLVING REGION'),
      coordinates: '--',
      temperature: '—',
      wind: '—',
      windDirection: '—',
      condition: t('UNKNOWN'),
      cloud: '—',
      precipitation: '—',
    },
  };
}

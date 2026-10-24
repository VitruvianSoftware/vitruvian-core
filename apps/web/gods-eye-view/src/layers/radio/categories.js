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

import { MUSIC_GENRES, CATEGORY_MATCHERS } from './policy.js';
import { t } from '../../i18n/index.js';

export function createCategories({
  state: layerState,
  services,
  parts,
  source,
}) {
  /** Normalize one directory tag to a stable, lower-case display token. */

  function normalizeRadioTag(value) {
    return String(value ?? '')
      .trim()
      .toLocaleLowerCase()
      .replace(/[_-]+/g, ' ')
      .replace(/\s+/g, ' ')
      .slice(0, 80);
  }

  function stationTags(station) {
    if (Array.isArray(station?.tags))
      return station.tags.map(normalizeRadioTag).filter(Boolean);
    return String(station?.tags ?? '')
      .split(',')
      .map(normalizeRadioTag)
      .filter(Boolean);
  }

  function hasTag(station, needles) {
    const tags = stationTags(station);
    return needles.some((needle) =>
      tags.some((tag) => tag === needle || tag.includes(needle)),
    );
  }

  function detectedGenres(station) {
    return MUSIC_GENRES.filter(([genre]) => hasTag(station, [genre])).map(
      ([genre]) => genre,
    );
  }

  /** Return whether a station belongs in a station-tag category. */

  function stationMatchesRadioCategory(station, categoryId) {
    if (categoryId === 'all') return true;
    if (categoryId.startsWith('genre:')) {
      return detectedGenres(station).includes(
        categoryId.slice('genre:'.length),
      );
    }
    if (categoryId === 'music') {
      return (
        detectedGenres(station).length > 0 ||
        hasTag(station, ['music', 'hits', 'songs'])
      );
    }
    if (categoryId === 'other') {
      return (
        !Object.entries(CATEGORY_MATCHERS).some(([id]) =>
          stationMatchesRadioCategory(station, id),
        ) && !stationMatchesRadioCategory(station, 'music')
      );
    }
    return hasTag(station, CATEGORY_MATCHERS[categoryId] || []);
  }

  /** Build canonical and detected-genre categories from station-level tags. */

  function buildRadioCategories(stations) {
    const rows = Array.isArray(stations) ? stations : [];
    const categories = [
      { id: 'all', label: t('All', { context: 'radio tag' }) },
      { id: 'news', label: t('News') },
      { id: 'talk', label: t('Talk') },
      { id: 'weather', label: t('Weather / Emergency') },
      { id: 'public-safety', label: t('Public Safety') },
      {
        id: 'aviation-marine',
        label: t('Aviation / Marine'),
      },
      {
        id: 'traffic-transit',
        label: t('Traffic / Transit'),
      },
      { id: 'music', label: t('Music') },
    ];

    for (const [genre, label] of MUSIC_GENRES) {
      const id = `genre:${genre}`;
      if (rows.some((station) => stationMatchesRadioCategory(station, id))) {
        categories.push({ id, label: t(label) });
      }
    }
    categories.push({ id: 'other', label: t('Other') });
    return categories.map((category) => ({
      ...category,
      color: parts.model.radioCategoryColor(category.id),
      count: rows.filter((station) =>
        stationMatchesRadioCategory(station, category.id),
      ).length,
    }));
  }

  /** Filter stations without changing the active stream or selection. */

  function filterRadioStations(stations, categoryId = 'all') {
    return (Array.isArray(stations) ? stations : []).filter((station) =>
      stationMatchesRadioCategory(station, categoryId),
    );
  }

  /** Return whether Radio Browser metadata identifies a station as English-language. */

  function isEnglishRadioStation(station) {
    const languages = Array.isArray(station?.languages)
      ? station.languages
      : [];
    return languages.some((language) => {
      const normalized = normalizeRadioTag(language);
      return (
        normalized === 'en' ||
        normalized === 'eng' ||
        normalized.startsWith('english')
      );
    });
  }
  return {
    normalizeRadioTag,
    stationTags,
    hasTag,
    detectedGenres,
    stationMatchesRadioCategory,
    buildRadioCategories,
    filterRadioStations,
    isEnglishRadioStation,
  };
}

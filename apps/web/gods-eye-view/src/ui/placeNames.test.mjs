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

// Preset place names show in the UI language at the presentation boundary
// (voice results, location pills, HUD); the preset data stays English.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { setLocale } from '../i18n/index.js';
import { CITY_POIS } from '../cityPois.js';
import { KNOWN_PLACE_NAMES, localizePlaceName } from './placeNames.js';
import { LocationControls } from './locationControls.js';

test.afterEach(() => setLocale('en'));

test('every preset city has a display name entry', () => {
  for (const city of Object.values(CITY_POIS))
    assert.ok(KNOWN_PLACE_NAMES.includes(city.name), city.name);
});

test('en: place names pass through unchanged', () => {
  setLocale('en');
  for (const name of KNOWN_PLACE_NAMES)
    assert.equal(localizePlaceName(name), name);
});

for (const [locale, tokyo, losAngeles] of [
  ['ru', 'Токио', 'Лос-Анджелес'],
  ['es', 'Tokio', 'Los Ángeles'],
]) {
  test(`${locale}: preset names are translated, other places shown as given`, () => {
    setLocale(locale);
    assert.equal(localizePlaceName('Tokyo'), tokyo);
    assert.equal(localizePlaceName('Los Angeles'), losAngeles);
    assert.equal(localizePlaceName('Ulaanbaatar'), 'Ulaanbaatar');
    assert.equal(localizePlaceName(undefined), undefined);
  });
}

function element() {
  return {
    children: [],
    dataset: {},
    textContent: '',
    addEventListener() {},
    removeEventListener() {},
    appendChild(child) {
      this.children.push(child);
    },
    replaceChildren() {
      this.children = [];
    },
  };
}

test('ru: location pills and the mini-status show the translated city', () => {
  setLocale('ru');
  const elements = {
    pills: element(),
    poiRow: element(),
    divider: element(),
    search: element(),
    searchToggle: element(),
    resetButtons: [],
    statusCity: element(),
    statusPoi: element(),
  };
  const doc = { ...element(), createElement: element };
  const cities = { tokyo: CITY_POIS.tokyo };
  const controls = new LocationControls({
    elements,
    cities,
    getExpandedCity: () => null,
    onCity() {},
    onPoi() {},
    onSearch() {},
    onReset() {},
    doc,
    requestFrame: () => 0,
    cancelFrame() {},
  });
  assert.equal(elements.pills.children[0].textContent, 'Токио');
  controls.renderStatus({ city: CITY_POIS.tokyo, currentPoi: null });
  assert.equal(elements.statusCity.textContent, '📍 Токио');
  assert.equal(CITY_POIS.tokyo.name, 'Tokyo');
});

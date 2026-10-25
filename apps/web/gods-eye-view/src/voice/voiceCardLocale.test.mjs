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

// The voice card names layers, sources and distances in the interface
// language; what the model receives stays English.
import test from 'node:test';
import assert from 'node:assert/strict';
import { setLocale } from '../i18n/index.js';
import { attachVoiceResult, planStepLabel } from './speech.js';
import { voiceCardView } from './voiceCardPresentation.js';

for (const locale of ['ru', 'es']) {
  test(`voice card is in ${locale} for a layer switch`, (t) => {
    t.after(() => setLocale('en'));
    setLocale(locale);
    const out = attachVoiceResult(
      'set_layer_visibility',
      {
        ok: true,
        layerId: 'flights',
        label: 'Live Flights',
        enabled: true,
        source: 'Flights',
      },
      { layerId: 'flights', enabled: true },
    );
    const view = voiceCardView({ steps: [], result: out });
    assert.doesNotMatch(out.display.title, /Live Flights/);
    assert.doesNotMatch(JSON.stringify(view), /Flights/);
  });
  test(`voice card distance is in ${locale}`, (t) => {
    t.after(() => setLocale('en'));
    setLocale(locale);
    const out = attachVoiceResult('fly_to_location', {
      ok: true,
      label: 'Paris',
      rangeM: 2500,
    });
    assert.doesNotMatch(out.display.lines[0], /2\.5 km/);
  });
  test(`plan label is in ${locale}`, (t) => {
    t.after(() => setLocale('en'));
    setLocale(locale);
    const a = planStepLabel('select_nearest_aircraft', {});
    const b = planStepLabel('set_layer_visibility', {
      layerId: 'earthquakes',
      enabled: true,
    });
    assert.doesNotMatch(a, /Here/);
    assert.doesNotMatch(b, /Earthquakes/);
  });
}

test('en: layer switch, distance and plan labels in English', () => {
  const out = attachVoiceResult(
    'set_layer_visibility',
    {
      ok: true,
      layerId: 'flights',
      label: 'Live Flights',
      enabled: true,
      source: 'Flights',
    },
    { layerId: 'flights', enabled: true },
  );
  assert.equal(out.say, 'Live Flights on.');
  assert.equal(out.display.title, 'Live Flights on');
  assert.deepEqual(out.display.sources, [{ label: 'Flights' }]);
  const fly = attachVoiceResult('fly_to_location', {
    ok: true,
    label: 'Paris',
    rangeM: 2500,
  });
  assert.equal(fly.display.lines[0].replace(/\s/g, ' '), 'Camera range 2.5 km');
  assert.equal(
    planStepLabel('select_nearest_aircraft', {}),
    'Nearest aircraft to Here',
  );
  assert.equal(
    planStepLabel('frame_overhead', { target: 'vessels' }),
    'Frame vessels',
  );
  // The plan names the layer as its result card does, not by its id.
  assert.equal(
    planStepLabel('set_layer_visibility', {
      layerId: 'earthquakes',
      enabled: true,
    }),
    'Earthquakes (24h) on',
  );
});

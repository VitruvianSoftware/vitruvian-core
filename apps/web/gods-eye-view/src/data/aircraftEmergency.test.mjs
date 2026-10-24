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

// src/data/aircraftEmergency.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  aircraftEmergency,
  emergencyBroadcastPhrase,
  isEmergency,
  normalizeSquawk,
} from './aircraftEmergency.js';

test('the three ICAO emergency squawks map to their kinds', () => {
  assert.equal(aircraftEmergency({ squawk: '7500' }).kind, 'unlawful');
  assert.equal(aircraftEmergency({ squawk: '7600' }).kind, 'nordo');
  const general = aircraftEmergency({ squawk: ' 7700 ' });
  assert.deepEqual(general, {
    kind: 'general',
    label: 'General emergency',
    severity: 'emergency',
    squawk: '7700',
    source: 'squawk',
  });
});

test('ordinary codes, blanks and non-octal values are not emergencies', () => {
  for (const squawk of ['1200', '7000', '2000', '', null, undefined, '7800'])
    assert.equal(aircraftEmergency({ squawk }), null, String(squawk));
  assert.equal(aircraftEmergency(), null);
  assert.equal(normalizeSquawk('7800'), null);
  assert.equal(normalizeSquawk(7700), '7700');
  assert.equal(normalizeSquawk('770'), null);
});

test('the ADS-B emergency field wins, and `none` defers to the squawk', () => {
  const minfuel = aircraftEmergency({ squawk: '4521', emergency: 'MinFuel' });
  assert.equal(minfuel.kind, 'minfuel');
  assert.equal(minfuel.severity, 'priority');
  assert.equal(minfuel.source, 'ads-b');
  assert.equal(minfuel.squawk, '4521');
  assert.equal(
    aircraftEmergency({ squawk: '7700', emergency: 'none' }).source,
    'squawk',
  );
  assert.equal(
    aircraftEmergency({ squawk: '7700', emergency: 'general' }).source,
    'squawk',
    'a code that names the status stays quotable',
  );
  assert.equal(
    aircraftEmergency({ squawk: '1200', emergency: 'general' }).source,
    'ads-b',
  );
  assert.equal(aircraftEmergency({ emergency: 'downed' }).kind, 'downed');
  assert.equal(aircraftEmergency({ emergency: 'none' }), null);
  assert.equal(aircraftEmergency({ emergency: 'reserved' }), null);
});

test('priority statuses are reported but are not emergencies', () => {
  assert.equal(isEmergency(aircraftEmergency({ squawk: '7700' })), true);
  assert.equal(
    isEmergency(aircraftEmergency({ emergency: 'lifeguard' })),
    false,
  );
  assert.equal(isEmergency(aircraftEmergency({ emergency: 'minfuel' })), false);
  assert.equal(isEmergency(null), false);
});

test('the broadcast phrase quotes a naming code, else attributes ADS-B', () => {
  assert.equal(
    emergencyBroadcastPhrase(aircraftEmergency({ squawk: '7700' })),
    'broadcasting squawk 7700 (general emergency)',
  );
  assert.equal(
    emergencyBroadcastPhrase(
      aircraftEmergency({ squawk: '1200', emergency: 'general' }),
    ),
    'ADS-B reports general emergency',
  );
  assert.equal(
    emergencyBroadcastPhrase(aircraftEmergency({ emergency: 'lifeguard' })),
    'ADS-B reports lifeguard (medical priority)',
  );
  assert.equal(emergencyBroadcastPhrase(null), null);
  assert.equal(emergencyBroadcastPhrase({ kind: 'reserved' }), null);
});

test('an emergency squawk outranks an ADS-B priority', () => {
  assert.equal(
    aircraftEmergency({ squawk: '7700', emergency: 'lifeguard' }).kind,
    'general',
  );
  assert.equal(
    aircraftEmergency({ squawk: '7500', emergency: 'minfuel' }).kind,
    'unlawful',
  );
});

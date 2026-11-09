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

import test from 'node:test';
import assert from 'node:assert/strict';
import { ACARTIA_CETACEAN_NAMES, acartiaSpeciesGroup } from './acartiaTaxa.js';

test('frozen cetacean names accept only normalized exact species or aliases', () => {
  assert.equal(Object.isFrozen(ACARTIA_CETACEAN_NAMES), true);
  assert.throws(() => ACARTIA_CETACEAN_NAMES.push('Whale shark'), TypeError);
  for (const name of ACARTIA_CETACEAN_NAMES) {
    assert.equal(acartiaSpeciesGroup(name), 'cetacean');
    assert.equal(acartiaSpeciesGroup(`  ${name.toUpperCase()}  `), 'cetacean');
    assert.equal(acartiaSpeciesGroup(`${name} or another animal`), null);
  }
  assert.equal(acartiaSpeciesGroup('Dall’s porpoise'), 'cetacean');
  assert.equal(acartiaSpeciesGroup('Pacific white–sided dolphin'), 'cetacean');
  assert.equal(acartiaSpeciesGroup('  HARBOR  PORPOISE '), 'cetacean');
});

test('clearly marine mammal names remain distinct from validated cetacean species', () => {
  for (const name of [
    'Harbor seal',
    'Phoca vitulina',
    'Sea otter',
    'Unidentified whale',
  ]) {
    assert.equal(acartiaSpeciesGroup(name), 'marine-mammal');
  }
  for (const name of [
    'Unknown',
    'Whale shark',
    'Elephant',
    '',
    null,
    { species: 'Orca' },
  ]) {
    assert.equal(acartiaSpeciesGroup(name), null);
  }
});

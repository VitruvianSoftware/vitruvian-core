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
import { setLocale } from './index.js';
import {
  cockpitUnitCase,
  formatCockpitDistance,
} from '../ui/cockpitPresentation.js';

test('Japanese cockpit distances keep the unit in its own case', () => {
  try {
    setLocale('ja');
    assert.equal(formatCockpitDistance(14000), '14 km');
    assert.equal(formatCockpitDistance(9500), '9.5 km');
    assert.equal(cockpitUnitCase('km'), 'km');
    setLocale('en');
    assert.equal(formatCockpitDistance(14000), '14 KM');
    assert.equal(cockpitUnitCase('km'), 'KM');
  } finally {
    setLocale('en');
  }
});

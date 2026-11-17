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
import {
  createEntityStore,
  entityRecord,
  readEntityRecord,
  withEntityRecord,
} from './entityRecords.js';

test('an entity record is made on first write and read back by the same entity', () => {
  const entity = {};
  assert.equal(readEntityRecord(entity), null);
  entityRecord(entity).trackedId = 'flights:a1b2c3';
  assert.equal(entityRecord(entity), entityRecord(entity), 'one record per entity');
  assert.equal(readEntityRecord(entity)?.trackedId, 'flights:a1b2c3');
  assert.equal(readEntityRecord({}), null, 'another entity has its own record');
});

test('the record lives in the app, not on the entity', () => {
  const entity = {};
  entityRecord(entity).labelModel = { title: 'DAL123', details: [] };
  assert.deepEqual(Object.keys(entity), []);
});

test('reading without an entity gives null', () => {
  assert.equal(readEntityRecord(null), null);
  assert.equal(readEntityRecord(undefined), null);
  assert.equal(readEntityRecord('flights:a1b2c3'), null);
});

test('withEntityRecord writes fields into the record and returns the entity', () => {
  const entity = withEntityRecord({ id: 'alpr:42' }, { trackedId: 'alpr:42' });
  assert.equal(entity.id, 'alpr:42');
  assert.equal(readEntityRecord(entity)?.trackedId, 'alpr:42');
  assert.equal(Object.hasOwn(entity, 'trackedId'), false);
});

test('a layer store is separate from the shared records and from other stores', () => {
  const entity = {};
  const a = createEntityStore();
  const b = createEntityStore();
  a.write(entity).canvasPosition = 1;
  assert.equal(a.read(entity)?.canvasPosition, 1);
  assert.equal(b.read(entity), null);
  assert.equal(readEntityRecord(entity), null);
  assert.equal(a.read(null), null);
  assert.deepEqual(Object.keys(entity), []);
});

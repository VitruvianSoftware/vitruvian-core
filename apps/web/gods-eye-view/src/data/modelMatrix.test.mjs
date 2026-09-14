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

// Regression test for the 3D-aircraft matrix-sharing bug — the "flickering like mad" + all-models-
// stacked-on-one-plane regression.
//
// The fleet/military layers build each aircraft's world transform with
//   Transforms.headingPitchRollToFixedFrame(pos, hpr, ellipsoid, undefined, RESULT)
// and assign it to `model.modelMatrix`. Cesium's Model.modelMatrix is a PLAIN FIELD (no cloning
// setter); Cesium clones it per frame in updateModelMatrix() by VALUE. So if every model is handed
// the SAME `result` object, they all end up rendering the LAST-written transform — every model
// stacked on one plane. Once the tracked model started writing that shared scratch EVERY frame
// (standalone-primitive change), the stack point oscillated frame-to-frame: the flicker.
//
// The fix: `_modelMatrix(pos, heading, result)` writes into each model's OWN `.modelMatrix`. This
// test locks the invariant at the Cesium level (the module's _modelMatrix is private and pulls the
// full engine, so we exercise the exact Cesium call it makes).
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { Transforms, Matrix4, Cartesian3, HeadingPitchRoll, Ellipsoid } from 'cesium';

const HPR = new HeadingPitchRoll(0, 0, 0);
const SF = Cartesian3.fromDegrees(-122.4, 37.7, 10000);
const LA = Cartesian3.fromDegrees(-118.2, 33.9, 9000);
const frame = (pos, result) =>
  Transforms.headingPitchRollToFixedFrame(pos, HPR, Ellipsoid.WGS84, undefined, result);

test('THE BUG: one shared scratch matrix stacks every model on the last-written position', () => {
  const scratch = new Matrix4();
  const a = frame(SF, scratch); // "model A" handed the shared scratch
  const b = frame(LA, scratch); // "model B" handed the same scratch — overwrites it in place
  assert.equal(a, b);                  // same object reference (the shared-scratch bug)
  assert.ok(Matrix4.equals(a, b));     // therefore same value -> A renders on top of B (stacking)
});

test('THE FIX: each model writing into its OWN matrix yields distinct transforms', () => {
  const matA = new Matrix4(); // model A's own .modelMatrix
  const matB = new Matrix4(); // model B's own .modelMatrix
  const a = frame(SF, matA);
  const b = frame(LA, matB);
  assert.notEqual(a, b);               // distinct objects
  assert.equal(a, matA);               // wrote in place into A's own matrix
  assert.equal(b, matB);
  assert.ok(!Matrix4.equals(a, b));    // distinct transforms — no stacking
  const ta = Matrix4.getTranslation(matA, new Cartesian3());
  const tb = Matrix4.getTranslation(matB, new Cartesian3());
  assert.ok(Cartesian3.distance(ta, tb) > 500000); // ~560 km SF->LA, not zero
});

test('re-running into the same own-matrix moves it in place (per-frame drive is safe)', () => {
  const mat = new Matrix4();
  frame(SF, mat);
  const t0 = Matrix4.getTranslation(mat, new Cartesian3());
  frame(LA, mat); // next frame: same model, new position
  const t1 = Matrix4.getTranslation(mat, new Cartesian3());
  assert.ok(Cartesian3.distance(t0, t1) > 500000); // it actually moved
});

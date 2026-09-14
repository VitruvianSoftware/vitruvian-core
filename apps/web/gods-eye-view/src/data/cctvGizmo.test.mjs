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

// src/data/cctvGizmo.test.mjs — pure drag math for the CCTV calibration gizmo
// (docs/superpowers/specs/2026-07-05-cctv-viewshed-gizmo-design.md §3c).
//
// Locks:
//   - closestParamOnAxis returns the metre-parameter along the AXIS of the
//     point nearest the mouse ray (the workhorse for arrow/range drags), and
//     refuses near-parallel configurations instead of exploding;
//   - rayPlaneIntersect refuses grazing rays (|dir·normal| < 0.08 — spec §5
//     precision guard) and behind-origin hits;
//   - ringAngle/signedAngleDelta give quadrant-correct, wrap-safe angles for
//     the heading/pitch ring drags.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import * as Cesium from 'cesium';
import {
  closestParamOnAxis,
  rayPlaneIntersect,
  ringAngle,
  signedAngleDelta,
} from './cctvGizmo.js';

const c3 = (x, y, z) => new Cesium.Cartesian3(x, y, z);

test('closestParamOnAxis: perpendicular ray hits the axis at its own offset', () => {
  // Axis along +X from origin. Ray shooting straight down (-Z) from (10, 0, 5):
  // nearest axis point is x=10 → t=10.
  const t = closestParamOnAxis(c3(10, 0, 5), c3(0, 0, -1), c3(0, 0, 0), c3(1, 0, 0));
  assert.ok(Math.abs(t - 10) < 1e-9, `expected 10, got ${t}`);
});

test('closestParamOnAxis: skew ray resolves to the geometric closest point', () => {
  // Axis +X. Ray from (0, 10, 0) toward (1, -1, 0)/√2 passes closest to the
  // axis around x=10 (it reaches y=0 at x=10).
  const dir = Cesium.Cartesian3.normalize(c3(1, -1, 0), new Cesium.Cartesian3());
  const t = closestParamOnAxis(c3(0, 10, 0), dir, c3(0, 0, 0), c3(1, 0, 0));
  assert.ok(Math.abs(t - 10) < 1e-6, `expected ~10, got ${t}`);
});

test('closestParamOnAxis: axis origin offset shifts the parameter', () => {
  const t = closestParamOnAxis(c3(10, 0, 5), c3(0, 0, -1), c3(4, 0, 0), c3(1, 0, 0));
  assert.ok(Math.abs(t - 6) < 1e-9, `expected 6, got ${t}`);
});

test('closestParamOnAxis: near-parallel ray/axis returns null', () => {
  assert.equal(closestParamOnAxis(c3(0, 1, 0), c3(1, 0, 0), c3(0, 0, 0), c3(1, 0, 0)), null);
  const nearly = Cesium.Cartesian3.normalize(c3(1, 1e-9, 0), new Cesium.Cartesian3());
  assert.equal(closestParamOnAxis(c3(0, 1, 0), nearly, c3(0, 0, 0), c3(1, 0, 0)), null);
});

test('rayPlaneIntersect: straight-on hit lands at the expected point', () => {
  const hit = rayPlaneIntersect(c3(0, 0, 10), c3(0, 0, -1), c3(0, 0, 0), c3(0, 0, 1));
  assert.ok(hit, 'expected a hit');
  assert.ok(Cesium.Cartesian3.distance(hit, c3(0, 0, 0)) < 1e-9);
});

test('rayPlaneIntersect: oblique hit resolves correctly', () => {
  const dir = Cesium.Cartesian3.normalize(c3(1, 0, -1), new Cesium.Cartesian3());
  const hit = rayPlaneIntersect(c3(0, 0, 5), dir, c3(0, 0, 0), c3(0, 0, 1));
  assert.ok(hit);
  assert.ok(Cesium.Cartesian3.distance(hit, c3(5, 0, 0)) < 1e-9, `got ${hit}`);
});

test('rayPlaneIntersect: grazing ray (|dir·n| < 0.08) returns null', () => {
  // dir almost in-plane: z component 0.05 < 0.08 threshold.
  const dir = Cesium.Cartesian3.normalize(c3(1, 0, -0.05), new Cesium.Cartesian3());
  assert.equal(rayPlaneIntersect(c3(0, 0, 5), dir, c3(0, 0, 0), c3(0, 0, 1)), null);
});

test('rayPlaneIntersect: plane behind the ray origin returns null', () => {
  assert.equal(rayPlaneIntersect(c3(0, 0, 10), c3(0, 0, 1), c3(0, 0, 0), c3(0, 0, 1)), null);
});

test('ringAngle: quadrant sweep in the (basisA, basisB) frame', () => {
  const center = c3(0, 0, 0);
  const a = c3(1, 0, 0);
  const b = c3(0, 1, 0);
  assert.ok(Math.abs(ringAngle(c3(5, 0, 0), center, a, b) - 0) < 1e-9);
  assert.ok(Math.abs(ringAngle(c3(0, 5, 0), center, a, b) - Math.PI / 2) < 1e-9);
  assert.ok(Math.abs(Math.abs(ringAngle(c3(-5, 0, 0), center, a, b)) - Math.PI) < 1e-9);
  assert.ok(Math.abs(ringAngle(c3(0, -5, 0), center, a, b) + Math.PI / 2) < 1e-9);
});

test('signedAngleDelta: shortest-path wrap', () => {
  const d2r = (d) => (d * Math.PI) / 180;
  assert.ok(Math.abs(signedAngleDelta(d2r(170), d2r(-170)) - d2r(20)) < 1e-9);
  assert.ok(Math.abs(signedAngleDelta(d2r(-170), d2r(170)) - d2r(-20)) < 1e-9);
  assert.ok(Math.abs(signedAngleDelta(d2r(10), d2r(30)) - d2r(20)) < 1e-9);
});

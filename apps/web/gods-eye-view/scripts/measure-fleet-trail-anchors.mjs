#!/usr/bin/env node
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
 * Re-measure the trail attachment point of every aircraft-layer fleet model
 * and print `src/data/fleetTrailAnchors.js`.
 *
 *   node scripts/measure-fleet-trail-anchors.mjs > src/data/fleetTrailAnchors.js
 *
 * Run it whenever a model under `public/models/fleet/` changes; the unit
 * suite (`src/data/fleetModels.test.mjs`) re-derives each value and fails
 * on a table that no longer matches its GLB.
 */
import fs from 'node:fs';
import path from 'node:path';
import { projectRoot } from './project-root.mjs';
import {
  fleetMesh,
  measuredTrailAnchor,
} from '../src/testSupport/fleetGlb.mjs';

/** Catalog categories the aircraft layers draw (ADS-B ground vehicles and balloons included). */
export const TRAIL_ANCHOR_CATEGORIES = ['aircraft', 'helicopters', 'other'];

const root = projectRoot(import.meta.url);
const dir = path.join(root, 'public', 'models', 'fleet');
const catalog = JSON.parse(
  fs.readFileSync(path.join(dir, 'catalog.json'), 'utf8'),
);
const rows = [];
for (const [name, model] of Object.entries(catalog)) {
  if (!TRAIL_ANCHOR_CATEGORIES.includes(model.category)) continue;
  const anchor = measuredTrailAnchor(
    await fleetMesh(path.join(dir, model.file)),
  );
  if (!anchor) continue;
  const [x, y] = anchor.map((value) => Number(value.toFixed(4)) || 0);
  rows.push(
    `  ${/^[a-z_]\w*$/.test(name) ? name : `'${name}'`}: Object.freeze([${x}, ${y}, 0]),`,
  );
}
process.stdout.write(`/**
 * Aft-belly trail attachment points of the fleet models the aircraft layers
 * draw, in raw glTF axes (X along the body, nose toward -X; Y up), metres
 * before scale, node transforms applied. Each is the point of the model's
 * centreline profile (its z = 0 slice) nearest its aft-belly bounding-box
 * corner: on the hull, aft, and on the centreline (see modelVisualAnchor.js).
 *
 * Written by scripts/measure-fleet-trail-anchors.mjs; re-measured against the
 * GLBs by fleetModels.test.mjs.
 */
export const FLEET_TRAIL_ANCHORS = Object.freeze({
${rows.join('\n')}
});
`);

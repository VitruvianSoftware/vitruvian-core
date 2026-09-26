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
import { createScenePackRegistry } from './registry.js';
import {
  effectiveShotHoldSec,
  shotRuntimeDurationSec,
  layerStatesForShot,
  visualStateForShot,
} from '../shotPresentation.js';

test('registered pack rules apply to another source without editing the Director or saved shots', () => {
  const recipe = {
    id: 'sample',
    runtimeHoldSecByBeat: { arrival: 6 },
    runtimeControlsByBeat: {
      arrival: { minimumHoldSec: 8, deferEvidenceUntilCameraSettled: true },
    },
  };
  let cancelled = 0;
  const packs = createScenePackRegistry({
    recipes: [recipe],
    adapters: [
      {
        resolveVisual: (_, visual) => ({ ...visual, mapStack: 'osm' }),
        cancelMotion: (getModule) => getModule('sample').cancelSceneMotion(),
      },
    ],
  });
  const shot = {
    id: 'a',
    sourcePackId: 'sample',
    durationSec: 2,
    holdSec: 1,
    visual: { style: 'normal' },
    layers: {
      sample: {
        enabled: true,
        params: { presentation: 'scene-beat', beatId: 'arrival' },
      },
    },
  };
  const scene = { id: 'scene', shots: [shot], releaseLayerIds: ['other'] };
  const before = structuredClone(shot);
  assert.equal(shotRuntimeDurationSec(scene, shot, packs), 10);
  assert.equal(effectiveShotHoldSec(scene, shot, packs), 8);
  const states = layerStatesForShot(scene, shot, packs, {
    cameraSettled: true,
  });
  assert.equal(states.sample.params.sceneControls.cameraSettled, true);
  assert.equal(states.sample.params.sceneContext.holdSec, 8);
  assert.equal(states.other.enabled, false);
  assert.equal(visualStateForShot(shot, packs, () => true).mapStack, 'osm');
  packs.cancelMotion(() => ({ cancelSceneMotion: () => cancelled++ }));
  assert.equal(cancelled, 1);
  assert.deepEqual(shot, before);
});

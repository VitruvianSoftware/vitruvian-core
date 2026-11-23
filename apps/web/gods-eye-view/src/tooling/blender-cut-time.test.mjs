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

// Reproduction: shot start/end times and timeline duration come from a different sum than frame ownership.
import test from 'node:test';
import assert from 'node:assert/strict';
import { sceneSeekState } from '../director/timeline.js';
import {
  effectiveShotHoldSec,
  shotRuntimeDurationSec,
} from '../scenes/shotPresentation.js';
import { createDefaultScenePacks } from '../scenes/packs/defaults.js';
import { exportCameraUsda } from './blenderCamera.js';

const packs = createDefaultScenePacks();
const pose = (heading) => ({
  lat: 0,
  lon: 0,
  alt: 0,
  heading,
  pitch: 0,
  roll: 0,
  altitudeReference: 'ellipsoid',
});
const shot = (id, heading, durationSec) => ({
  id,
  durationSec,
  holdSec: 0,
  camera: pose(heading),
  move: { from: pose(heading), easing: 'linear' },
});
const options = {
  origin: { lat: 0, lon: 0, height: 0 },
  fps: { numerator: 30, denominator: 1 },
  width: 1920,
  height: 1080,
  horizontalFovDegrees: 90,
};
const dur = (s, sh) => shotRuntimeDurationSec(s, sh, packs);
const hold = (s, sh) => effectiveShotHoldSec(s, sh, packs);

for (const [name, count, seconds] of [
  ['nine shot cut', 9, 0.7],
  ['six shot seek total', 6, 0.2],
]) {
  test(name, () => {
    const scene = {
      id: 'scene',
      title: 'S',
      shots: Array.from({ length: count }, (_, i) =>
        shot(`s${i + 1}`, i * 10, seconds),
      ),
    };
    const { samples, usda } = exportCameraUsda(
      { version: 6, scenes: [scene] },
      options,
    );
    for (const [attribute, field] of [
      ['gevStartTimeSec', 'startTimeSec'],
      ['gevEndTimeSec', 'endTimeSec'],
    ]) {
      const times = [
        ...usda.matchAll(new RegExp(`userProperties:${attribute} = (.+)`, 'g')),
      ];
      assert.deepEqual(
        times.map(([, value]) => Number(value)),
        samples.shots.map((shot) => shot[field]),
        attribute,
      );
    }
    // Each frame's camera still follows Director seeking.
    const total = scene.shots.reduce((sum, sh) => sum + dur(scene, sh), 0);
    for (const frame of samples.frames)
      assert.equal(
        frame.shotId,
        sceneSeekState(scene, frame.timeSec / total, dur, hold).shot.id,
      );
    // The published duration seeks to the same owner.
    for (const frame of samples.frames)
      assert.equal(
        frame.shotId,
        sceneSeekState(
          scene,
          frame.timeSec / samples.timeline.durationSec,
          dur,
          hold,
        ).shot.id,
        `published total, frame ${frame.frame}`,
      );
    // Documented rule: a shot starts at the first sampled time at or after its start time.
    for (const s of samples.shots) {
      assert.ok(
        samples.frames[s.frameStart - 1].timeSec >= s.startTimeSec,
        `${s.id} starts before startTimeSec`,
      );
      if (s.frameStart > 1)
        assert.ok(
          samples.frames[s.frameStart - 2].timeSec < s.startTimeSec,
          `${s.id}: frame ${s.frameStart - 1} at ${samples.frames[s.frameStart - 2].timeSec} s is at/after startTimeSec ${s.startTimeSec} but belongs to the previous shot`,
        );
    }
  });
}

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
import { createLifecycle } from './lifecycle.js';
import { createRendering } from './rendering.js';
import { createState } from './state.js';
import { bindFakeDraw } from '../../testSupport/fakeDrawPort.mjs';

const overlays = () => ({
  clearOverlaySource() {},
  setOverlaySourceVisible() {},
  setOverlayEntries() {},
});

/** A viewer whose data sources and entities would record what was done to them. */
function recordingViewer() {
  const calls = [];
  return {
    calls,
    dataSources: {
      add: (source) => calls.push(['add', source]),
      remove: (source, destroy) => calls.push(['remove', source, destroy]),
    },
    entities: { remove: (entity) => calls.push(['removeEntity', entity]) },
    scene: { requestRender() {} },
  };
}

test('the stations draw sets are made once, cluster on camera moves, and go with their listener', () => {
  const services = {
    ground: { cachedGroundFloor: () => null },
    overlays: overlays(),
    render: { governorRequestRender() {} },
  };
  const state = createState({ services });
  const rendering = createRendering({ state, services, parts: {} });
  const viewer = recordingViewer();
  const changed = new Set();
  const camera = {
    pose: () => null,
    on(event, cb) {
      assert.equal(event, 'changed');
      changed.add(cb);
      return () => changed.delete(cb);
    },
  };
  const { draw, unbind } = bindFakeDraw(viewer, { camera });
  try {
    state._viewer = viewer;

    rendering.installDataSource(viewer);
    const ids = () =>
      [...draw.sets.values()]
        .filter((set) => !set.disposed)
        .map((set) => `${set.kind}:${set.spec.id.replace(/^radio:\d+:/, '')}`);
    assert.deepEqual(ids(), [
      'points:stations',
      'points:clusters',
      'points:selected',
      'icons:selected-bracket',
    ]);
    assert.equal(changed.size, 1, 'clusters again as the camera moves');
    rendering.installDataSource(viewer);
    assert.equal(ids().length, 4, 'made once');

    rendering.setStationsShown(false);
    assert.equal(draw.find('radio:').show, false);
    assert.equal(
      [...draw.sets.values()].find((set) => set.spec.id.endsWith(':clusters'))
        .show,
      false,
    );

    rendering.removeDataSource();
    assert.deepEqual(ids(), [], 'every set goes');
    assert.equal(changed.size, 0, 'and its camera listener');
    assert.deepEqual(viewer.calls, [], 'no Cesium data source or entity');
  } finally {
    unbind();
  }
});

test("the lifecycle leaves the stations' draw sets to the rendering part", () => {
  const services = { overlays: overlays() };
  const state = createState({ services });
  const done = [];
  const record =
    (name) =>
    (...args) =>
      done.push([name, ...args]);
  const parts = {
    clustering: {
      resetRadioClusterOverlayIdentities() {},
      emptyRadioOverlayDiagnostics: () => ({}),
    },
    playback: { installAudio() {}, stopRadioPlayback() {} },
    rendering: {
      installDataSource: record('installDataSource'),
      setStationsShown: record('setStationsShown'),
      removeSelectionEntity: record('removeSelectionEntity'),
      removeDataSource: record('removeDataSource'),
    },
    interaction: {
      syncRadioLifecyclePresentation() {},
      removeInteraction() {},
    },
    presentation: { emitState() {} },
    navigation: { invalidateRadioCameraNavigation() {} },
    tuning: { endRadioTuning() {} },
    volume: { cancelRadioVolumeTransition() {} },
  };
  const { methods } = createLifecycle({ state, services, parts });
  const viewer = recordingViewer();

  methods.init(viewer);
  assert.deepEqual(done, [
    ['installDataSource', viewer],
    ['setStationsShown', false],
  ]);
  done.length = 0;
  methods.destroy();
  assert.deepEqual(done, [
    ['setStationsShown', false],
    ['removeSelectionEntity'],
    ['removeDataSource'],
  ]);
  assert.deepEqual(viewer.calls, [], 'the lifecycle drives no viewer itself');
  assert.equal(state._viewer, null);
});

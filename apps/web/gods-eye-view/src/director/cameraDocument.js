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

import {
  fields,
  string,
  number,
  optional,
  array,
  fail,
  uniqueId,
} from './documentFields.js';

const POSITION = { lat: [-90, 90], lon: [-180, 180], alt: [-12000, 1e9] };
const ORIENTATION = {
  heading: [-360, 360],
  pitch: [-90, 90],
  roll: [-360, 360],
};
function coordinates(value, path, bounds, required, legacy) {
  for (const [key, range] of Object.entries(bounds)) {
    if (required || Object.hasOwn(value, key))
      number(value[key], `${path}.${key}`, ...range, legacy);
  }
}
function reference(value, path) {
  if (value !== 'ellipsoid')
    fail(
      path,
      'expected ellipsoid height in meters; terrain-relative heights are not supported',
    );
}
function pose(value, path, version, anchorIds, explicit = false) {
  const anchored = version >= 4 && Object.hasOwn(value || {}, 'anchorId');
  fields(value, path, [
    ...Object.keys(ORIENTATION),
    ...(anchored
      ? ['anchorId']
      : [
          ...Object.keys(POSITION),
          ...(version >= 4 ? ['altitudeReference'] : []),
        ]),
  ]);
  coordinates(value, path, ORIENTATION, false, version < 3);
  if (anchored) {
    string(value.anchorId, `${path}.anchorId`);
    if (!anchorIds.has(value.anchorId))
      fail(`${path}.anchorId`, 'unknown scene anchor');
  } else {
    coordinates(value, path, POSITION, explicit, version < 3);
    if (explicit || Object.hasOwn(value, 'altitudeReference'))
      reference(value.altitudeReference, `${path}.altitudeReference`);
  }
}

/** Validate scene-local anchor IDs, camera references and explicit motion without reading terrain or applying state. */
export function validateSceneCameras(scene, path, version) {
  const anchorIds = new Set();
  optional(scene, 'anchors', path, (anchors, field) => {
    array(anchors, field, 1024);
    anchors.forEach((anchor, i) => {
      const at = `${field}[${i}]`;
      fields(anchor, at, [
        'id',
        'title',
        ...Object.keys(POSITION),
        'altitudeReference',
      ]);
      string(anchor.id, `${at}.id`);
      uniqueId(anchor, at, anchorIds);
      optional(anchor, 'title', at, (v, p) => string(v, p, 4096));
      coordinates(anchor, at, POSITION, true, false);
      reference(anchor.altitudeReference, `${at}.altitudeReference`);
    });
  });
  scene.shots.forEach((shot, index) => {
    const at = `${path}.shots[${index}]`;
    optional(shot, 'move', at, (move, field) => {
      fields(move, field, ['from', 'easing']);
      if (!['linear', 'cubic-in-out'].includes(move.easing))
        fail(`${field}.easing`, 'expected linear or cubic-in-out');
      pose(move.from, `${field}.from`, version, anchorIds, true);
      pose(shot.camera, `${at}.camera`, version, anchorIds, true);
      number(shot.durationSec, `${at}.durationSec`, 0.2, 86400, false);
      number(shot.holdSec, `${at}.holdSec`, 0, 86400, false);
    });
    optional(shot, 'camera', at, (camera, field) =>
      pose(camera, field, version, anchorIds),
    );
  });
}

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

import { parseSceneDocument, stringifySceneDocument } from './document.js';

/** Build a validated immutable edit while preserving IDs, existing content and provenance. */
export function editSceneDetails(
  project,
  sceneId,
  shotId,
  sceneDetails,
  shotDetails,
) {
  const copy = parseSceneDocument(stringifySceneDocument(project));
  const scene = copy.scenes.find((s) => s.id === sceneId),
    shot = scene?.shots.find((s) => s.id === shotId);
  if (!scene || !shot) throw new Error('Select a scene and shot first');
  for (const key of Object.keys(sceneDetails))
    if (!['anchors', 'dataPacks'].includes(key))
      throw new Error('Unsupported scene detail');
  for (const key of Object.keys(shotDetails))
    if (
      ![
        'camera',
        'move',
        'durationSec',
        'holdSec',
        'dataPackIds',
        'interactions',
      ].includes(key)
    )
      throw new Error('Unsupported shot detail');
  for (const key of ['anchors', 'dataPacks']) {
    delete scene[key];
    if (Object.hasOwn(sceneDetails, key)) scene[key] = sceneDetails[key];
  }
  for (const key of [
    'camera',
    'move',
    'durationSec',
    'holdSec',
    'dataPackIds',
    'interactions',
  ]) {
    delete shot[key];
    if (Object.hasOwn(shotDetails, key)) shot[key] = shotDetails[key];
  }
  return parseSceneDocument(stringifySceneDocument(copy));
}

/** Export exactly one authored scene; no live state or service configuration is consulted. */
export function selectSceneDocument(project, sceneId) {
  const copy = parseSceneDocument(stringifySceneDocument(project));
  const scene = copy.scenes.find((s) => s.id === sceneId);
  if (!scene) throw new Error('Select a scene first');
  return { ...copy, scenes: [scene] };
}

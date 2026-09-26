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

import { BUNDLE_SOURCE } from './bundle.js';

/** Describe an import without fetching assets, applying state or exposing source configuration. */
export function describeSceneShare(
  { project, assets },
  { sourceIds = [], layerIds = [] } = {},
) {
  const sources = new Set(sourceIds),
    layers = new Set(layerIds);
  const packs = project.scenes.flatMap((scene) =>
    (scene.dataPacks || []).map((pack) => ({
      scene: scene.title || scene.id,
      id: pack.id,
      path: pack.source.path,
      attribution: pack.attribution,
      status:
        pack.source.adapter === BUNDLE_SOURCE
          ? assets.has(pack.source.path)
            ? 'Included in bundle'
            : 'Missing bundle file — reimport its bundle'
          : sources.has(pack.source.adapter)
            ? 'Source configured; file checked when loaded'
            : 'Source unavailable',
    })),
  );
  return {
    scenes: project.scenes.length,
    shots: project.scenes.reduce((n, s) => n + s.shots.length, 0),
    packs,
    missingLayers: [
      ...new Set(
        project.scenes.flatMap((s) =>
          s.shots.flatMap((shot) => Object.keys(shot.layers || {})),
        ),
      ),
    ].filter((id) => !layers.has(id)),
    externalContent: project.scenes.some(
      (s) =>
        s.appliedShotPacks?.length || s.shots.some((shot) => shot.sourcePackId),
    ),
    bundledBytes: [...assets.values()].reduce((n, a) => n + a.bytes.length, 0),
  };
}

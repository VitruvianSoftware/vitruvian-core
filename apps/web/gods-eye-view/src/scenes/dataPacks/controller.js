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

import { createDataPackSession } from '../../director/packs/session.js';
import { createPackPresentations } from './presentation.js';

/** Bind selected shot packs to one viewer and expose copied lifecycle diagnostics. */
export function createSceneDataPacks(viewer, { sources = {} } = {}) {
  const targets = new Map();
  const session = createDataPackSession({
    sources,
    adapters: createPackPresentations(viewer, targets),
  });
  return {
    ...session,
    sourceIds: () => Object.keys(sources),
    getTargets: () => new Map(targets),
    apply(scene, shot, token) {
      const wanted = new Set(shot.dataPackIds || []);
      return session.load(
        (scene.dataPacks || []).filter((pack) => wanted.has(pack.id)),
        { anchors: scene.anchors, signal: token?.signal },
      );
    },
  };
}

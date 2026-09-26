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

import fs from 'node:fs';
import path from 'node:path';
import { poseHash } from '../../../src/data/cctvFootprint.js';

/** Sidecar written by scripts/precompute-cctv-heights.mjs. */
export const DEFAULT_GROUND_HEIGHTS_FILE =
  'src/data/local_data/cctv_ground_heights/cctv_ground_heights.json';

/** @type {{path:string, mtimeMs:number, cameras:object}|null} */
let _cache = null;

/**
 * Load the precomputed ground-height sidecar (heights under each camera's mount
 * and monitor-plane support points, aligned to the Google 3D Tiles surface). Cached by file mtime so a
 * catalog refresh re-reads only when the file changed. Missing or malformed
 * files mean "no shipped heights", never an error.
 * @param {string} sourceRoot
 * @returns {Record<string, object>} camera id → sidecar entry
 */
export function loadGroundHeights(sourceRoot = process.cwd()) {
  const file =
    process.env.CCTV_GROUND_HEIGHTS_FILE || DEFAULT_GROUND_HEIGHTS_FILE;
  const resolved = path.isAbsolute(file)
    ? file
    : path.resolve(sourceRoot, file);
  try {
    const stat = fs.statSync(resolved);
    if (_cache && _cache.path === resolved && _cache.mtimeMs === stat.mtimeMs) {
      return _cache.cameras;
    }
    const parsed = JSON.parse(fs.readFileSync(resolved, 'utf8'));
    const cameras =
      parsed &&
      typeof parsed === 'object' &&
      parsed.cameras &&
      typeof parsed.cameras === 'object'
        ? parsed.cameras
        : {};
    _cache = { path: resolved, mtimeMs: stat.mtimeMs, cameras };
    return cameras;
  } catch {
    _cache = null;
    return {};
  }
}

/**
 * Attach a shipped entry to each served source whose id has one AND whose
 * nominal pose still hashes to what the entry was sampled for. A pack whose
 * feed moved a camera or changed its pose simply loses the shipped value and
 * falls back to runtime placement.
 * @param {Array<object>} sources - Normalized served sources.
 * @param {Record<string, object>} entries - Sidecar cameras map.
 * @returns {Array<object>} The same sources, `groundHeights` attached where valid.
 */
export function joinGroundHeights(sources, entries) {
  if (!entries || typeof entries !== 'object') return sources;
  for (const source of sources) {
    const entry = entries[source.id];
    if (!entry || entry.status !== 'ok' || !Number.isFinite(entry.mountGroundM))
      continue;
    if (entry.poseHash !== poseHash(source)) continue;
    const supports = {};
    for (const [key, value] of Object.entries(entry.supports || {})) {
      if (Number.isFinite(value)) supports[key] = value;
    }
    source.groundHeights = {
      poseHash: entry.poseHash,
      mountGroundM: entry.mountGroundM,
      supports,
    };
  }
  return sources;
}

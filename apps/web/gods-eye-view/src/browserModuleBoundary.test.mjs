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

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const SRC_ROOT = fileURLToPath(new URL('.', import.meta.url));

/** Every browser-built module under src/ — the test files are Node-only. */
function browserModules(directory = SRC_ROOT) {
  const files = [];
  for (const entry of readdirSync(directory, { withFileTypes: true })) {
    const absolute = path.join(directory, entry.name);
    if (entry.isDirectory()) files.push(...browserModules(absolute));
    else if (entry.isFile() && entry.name.endsWith('.js')) files.push(absolute);
  }
  return files.sort();
}

test('no browser-built module imports a Node core module', () => {
  // Vite externalizes `node:*` for the browser and only WARNS, so a stray
  // import survives the build and turns into a runtime failure the moment the
  // guard around it is wrong. src/data/naturalEarthRegions.js and
  // src/data/neighborhoodPolygons.js both carried one to read their bundled
  // JSON packs under node:test; an import attribute serves both runtimes.
  const offenders = [];
  for (const file of browserModules()) {
    const source = readFileSync(file, 'utf8');
    // Static `from 'node:fs'` and dynamic `import('node:fs')`, quoted either way.
    if (/\bfrom\s*['"]node:|\bimport\s*\(\s*(?:\/\*[^*]*\*\/\s*)?['"]node:/.test(source)) {
      offenders.push(path.relative(SRC_ROOT, file).split(path.sep).join('/'));
    }
  }

  assert.deepEqual(offenders, [], `Node core imports reached the browser build: ${offenders.join(', ')}`);
});

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

import assert from 'node:assert/strict';
import test from 'node:test';
import { execFileSync } from 'node:child_process';
import {
  mkdtempSync,
  mkdirSync,
  writeFileSync,
  rmSync,
  symlinkSync,
} from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { analyzeModule } from '../../scripts/module-analysis.mjs';
import { checkImportDirections } from '../../scripts/check-import-directions.mjs';

function fixture(t, exports = {}) {
  const root = mkdtempSync(path.join(os.tmpdir(), 'gev-directions-'));
  t.after(() => rmSync(root, { recursive: true, force: true }));
  execFileSync('git', ['init', '--quiet'], { cwd: root });
  const write = (name, source = '') => {
    mkdirSync(path.dirname(path.join(root, name)), { recursive: true });
    writeFileSync(path.join(root, name), source);
  };
  write(
    'package.json',
    JSON.stringify({ name: '@gods-eye-view/core', exports }),
  );
  write('src/data/feedState.js');
  return { root, write };
}

test('module analysis parses dependencies and platform references without reading comments or property labels', () => {
  assert.deepEqual(
    analyzeModule(
      "// import('node:fs'); document\nimport x from 'one'; export { x } from 'two'; export * from 'three'; import('four'); const data = { document: 1 }; data.window;",
    ),
    { imports: ['one', 'two', 'three', 'four'], browser: [] },
  );
  assert.deepEqual(
    analyzeModule(
      "const data = { element: document }; globalThis['navigator'];",
    ).browser,
    ['document', 'navigator'],
  );
  assert.throws(() => analyzeModule('import(name)'), /Computed/);
  assert.throws(() => analyzeModule("require('node:fs')"), /ES imports/);
});

test('portable sources can share records, and standalone can assemble rendering', (t) => {
  const { root, write } = fixture(t, {
    './layers/demo/source': './src/layers/demo/source.js',
  });
  write('src/layers/demo/source.js', "export { read } from './records.js';");
  write('src/layers/demo/records.js', 'export const read = (value) => value;');
  write('src/standalone/catalog.js', "import '../layers/demo/index.js';");
  write('src/layers/demo/index.js', "import * as Cesium from 'cesium';");
  assert.equal(checkImportDirections(root).modules, 5);
});

for (const [name, files, pattern] of [
  [
    'unreachable source imports rendering',
    {
      'src/layers/demo/source.js': "import './rendering.js';",
      'src/layers/demo/rendering.js': '',
    },
    /Source imports rendering/,
  ],
  [
    'source reaches a platform through a record helper',
    {
      'src/layers/demo/source.js': "import './records.js';",
      'src/layers/demo/records.js': "import 'cesium';",
    },
    /reaches platform\/rendering/,
  ],
  [
    'source reaches a DOM helper',
    {
      'src/sources/demo.js': "import '../data/helper.js';",
      'src/data/helper.js': 'export const view = () => globalThis.document;',
    },
    /reaches browser globals/,
  ],
  [
    'browser imports Node without prefix',
    { 'src/unused.mjs': "import 'fs/promises';" },
    /Node builtin/,
  ],
  [
    'browser hides Node outside src',
    {
      'src/unused.js': "import '../shared/helper.js';",
      'shared/helper.js': "export * from 'node:fs';",
    },
    /Browser graph reaches Node/,
  ],
  [
    'browser imports server',
    {
      'src/data/demo.js': "import '../../server/helper.js';",
      'server/helper.js': '',
    },
    /Browser imports server/,
  ],
  [
    'reusable module selects standalone',
    {
      'src/app/demo.js': "import '../standalone/catalog.js';",
      'src/standalone/catalog.js': '',
    },
    /Reusable module imports standalone/,
  ],
  [
    'provider selects application setup',
    {
      'server/providers/demo.js': "import '../standalone/key-setup.js';",
      'server/standalone/key-setup.js': '',
    },
    /Provider imports application/,
  ],
  [
    'voice controls reach protocol indirectly',
    {
      'src/voice/sessionCommands.js': "import './helper.js';",
      'src/voice/helper.js': "import './realtimeSession.js';",
      'src/voice/realtimeSession.js': '',
    },
    /Common voice controls import protocol/,
  ],
  [
    'dynamic import cannot evade direction',
    { 'src/app/demo.js': "const target = './module.js'; import(target);" },
    /Computed/,
  ],
  [
    'browser imports test helper',
    {
      'src/app/demo.js': "import '../testSupport/helper.js';",
      'src/testSupport/helper.js': '',
    },
    /non-runtime owner/,
  ],
]) {
  test(`rejects ${name}`, (t) => {
    const { root, write } = fixture(t);
    for (const [file, body] of Object.entries(files)) write(file, body);
    assert.throws(() => checkImportDirections(root), pattern);
  });
}

test('self package imports cannot evade portable ownership', (t) => {
  const { root, write } = fixture(t, { './view': './src/ui/view.js' });
  write('src/sources/demo.js', "import '@gods-eye-view/core/view';");
  write('src/ui/view.js');
  assert.throws(() => checkImportDirections(root), /Source imports rendering/);
});

test('compatibility exceptions are limited to the two existing composition entries', (t) => {
  const { root, write } = fixture(t);
  write('src/ui.js', "import './standalone/catalog.js';");
  write('src/standalone/catalog.js');
  write('server/providers/local.js', "import '../standalone/key-setup.js';");
  write('server/standalone/key-setup.js');
  assert.doesNotThrow(() => checkImportDirections(root));
  write('src/ui/new.js', "import '../standalone/catalog.js';");
  assert.throws(
    () => checkImportDirections(root),
    /Reusable module imports standalone/,
  );
});

test('symlink aliases do not hide renderer ownership', (t) => {
  const { root, write } = fixture(t);
  write('src/sources/demo.js', "import './helper/view.js';");
  write('src/ui/view.js');
  // Directory junctions exercise the same resolved edge without Windows symlink privileges.
  symlinkSync(
    path.join(root, 'src/ui'),
    path.join(root, 'src/sources/helper'),
    'junction',
  );
  assert.throws(() => checkImportDirections(root), /rendering|symlinks/);
});

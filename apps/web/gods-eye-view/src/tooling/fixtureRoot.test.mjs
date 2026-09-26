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
import { mkdir, mkdtemp, realpath, rm, symlink } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { makeFixtureRoot } from './fixtureRoot.mjs';

// Creating a symlink needs a privilege Windows does not grant by default, and
// Windows reads its temp directory from other variables than TMPDIR. The case
// therefore covers macOS and Linux; a Windows equivalent would have to build a
// directory junction and set TEMP.
const symlinkTest = process.platform === 'win32' ? test.skip : test;

symlinkTest(
  'a fixture root is physical even when the temp root is a symlink',
  async (t) => {
    // macOS reaches its own temp directory through a symlink and Linux does
    // not, so build one explicitly: without it this check would pass on the
    // Linux runner while every Mac contributor still saw the failure it exists
    // to prevent.
    const scratch = await realpath(
      await mkdtemp(path.join(tmpdir(), 'gev-fixture-root-')),
    );
    t.after(() => rm(scratch, { recursive: true, force: true }));
    const physical = path.join(scratch, 'physical');
    const viaLink = path.join(scratch, 'link');
    await mkdir(physical);
    await symlink(physical, viaLink);

    const before = process.env.TMPDIR;
    process.env.TMPDIR = viaLink;
    t.after(() => {
      if (before === undefined) delete process.env.TMPDIR;
      else process.env.TMPDIR = before;
    });
    // Fail rather than pass vacuously: if the temp root is not the symlink,
    // the condition under test was never set up.
    assert.equal(
      tmpdir(),
      viaLink,
      'the symlinked temp root was not in force, so nothing was exercised',
    );

    const root = await makeFixtureRoot('gev-fixture-case-');
    assert.equal(
      root,
      await realpath(root),
      'the fixture root still contains a symlink',
    );
    assert.ok(
      root.startsWith(`${physical}${path.sep}`),
      `${root} is not under the physical temp root ${physical}`,
    );
  },
);

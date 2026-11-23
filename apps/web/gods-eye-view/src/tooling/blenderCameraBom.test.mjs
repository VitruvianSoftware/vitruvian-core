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
import {
  mkdtempSync,
  writeFileSync,
  readFileSync,
  rmSync,
  existsSync,
} from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync, execFileSync } from 'node:child_process';
import { SCENE_DOCUMENT_LIMITS } from '../director/document.js';

const cli = fileURLToPath(
  new URL('../../tools/export-blender-camera.mjs', import.meta.url),
);
const pose = (c = {}) => ({
  lat: 0,
  lon: 0,
  alt: 10,
  heading: 0,
  pitch: 0,
  roll: 0,
  ...c,
});
const doc = (shots, extra = {}) => ({
  version: 6,
  scenes: [{ id: 'scene', title: 'Synthetic', shots, ...extra }],
});
const one = [{ id: 'a', durationSec: 1, holdSec: 0, camera: pose() }];
const argsFor = (input, output, fps = '30') => [
  cli,
  '--input',
  input,
  '--output',
  output,
  '--origin',
  '0,0,0',
  '--fps',
  fps,
  '--width',
  '1920',
  '--height',
  '1080',
  '--horizontal-fov-deg',
  '60',
];
const dir = () => mkdtempSync(join(tmpdir(), 'gev-camera-repro-'));

test('a UTF-8 BOM scene exports like the same scene without BOM (Director import accepts both)', () => {
  const d = dir();
  try {
    const body = Buffer.from(JSON.stringify(doc(one)));
    const plain = join(d, 'plain.json');
    const bom = join(d, 'bom.json');
    writeFileSync(plain, body);
    writeFileSync(bom, Buffer.concat([Buffer.from([0xef, 0xbb, 0xbf]), body]));
    const a = spawnSync(process.execPath, argsFor(plain, join(d, 'a.usda')), {
      encoding: 'utf8',
    });
    const b = spawnSync(process.execPath, argsFor(bom, join(d, 'b.usda')), {
      encoding: 'utf8',
    });
    assert.equal(a.status, 0, a.stderr);
    assert.equal(b.status, 0, b.stderr);
    assert.deepEqual(
      readFileSync(join(d, 'b.usda')),
      readFileSync(join(d, 'a.usda')),
    );
  } finally {
    rmSync(d, { recursive: true, force: true });
  }
});

test('the input file size limit includes the UTF-8 BOM', () => {
  const d = dir();
  try {
    const input = join(d, 'scene.json');
    const output = join(d, 'camera.usda');
    const scene = JSON.stringify(doc(one)).padEnd(
      SCENE_DOCUMENT_LIMITS.bytes,
      ' ',
    );
    writeFileSync(input, '\uFEFF' + scene);
    const result = spawnSync(process.execPath, argsFor(input, output), {
      encoding: 'utf8',
    });
    assert.equal(result.status, 1);
    assert.match(result.stderr, /exceeds 5 MiB/);
    assert.equal(existsSync(output), false);
  } finally {
    rmSync(d, { recursive: true, force: true });
  }
});

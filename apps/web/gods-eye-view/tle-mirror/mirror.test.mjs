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
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { celestrakTleUrl } from '../src/data/spaceProviderRequests.js';
import { MIRRORED_GROUPS, celestrakGroupUrl, hasTle, mirror } from './mirror.mjs';

const APP = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const read = (file) => fs.readFileSync(path.join(APP, file), 'utf8');

/** The quoted strings in the array literal that `const <name> = [` opens. */
function arrayStrings(source, name, key) {
  const start = source.indexOf(`const ${name} = [`);
  assert.ok(start >= 0, `${name} is declared`);
  const body = source.slice(start, source.indexOf('];', start));
  const pattern = key ? new RegExp(`${key}:\\s*'([^']+)'`, 'g') : /'([^']+)'/g;
  return [...body.matchAll(pattern)].map((match) => match[1]);
}

/** Every /api/celestrak/<literal> the client's code requests. */
function literalGroups(dir) {
  const groups = [];
  for (const entry of fs.readdirSync(path.join(APP, dir), { withFileTypes: true })) {
    const file = path.join(dir, entry.name);
    if (entry.isDirectory()) groups.push(...literalGroups(file));
    else if (/\.m?js$/.test(entry.name) && !/\.test\./.test(entry.name)) {
      for (const match of read(file).matchAll(/['"`]\/api\/celestrak\/([a-z0-9-]+)['"`]/g)) {
        groups.push(match[1]);
      }
    }
  }
  return groups;
}

test('the mirror carries every group the client requests', () => {
  const requested = new Set([
    ...arrayStrings(read('src/layers/satellites/policy.js'), 'CATALOG_GROUPS', 'path'),
    ...arrayStrings(read('src/tools/queries/space.js'), 'GROUPS'),
    ...literalGroups('src'),
  ]);
  assert.ok(requested.has('stations') && requested.has('active'), 'the scan finds the client groups');
  const missing = [...requested].filter((group) => !MIRRORED_GROUPS.includes(group));
  assert.deepEqual(missing, [], 'requested by the client but not mirrored');
});

test('the mirror fetches the URL the server would', () => {
  for (const group of MIRRORED_GROUPS) {
    assert.equal(celestrakGroupUrl(group), celestrakTleUrl(group).toString());
  }
});

test('a failed group keeps the file it had; good groups are refreshed; one retry', async () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'tle-mirror-'));
  try {
    fs.writeFileSync(path.join(dir, 'visual.txt'), 'previous visual\n');
    const tle = 'ISS (ZARYA)\n1 25544U 98067A   26280.50000000  .00010000  00000-0  18000-3 0  9990\n2 25544  51.6400 100.0000 0005000 100.0000 260.0000 15.50000000400000\n';
    const calls = [];
    const responses = {
      stations: () => new Response(tle),
      visual: () => new Response('<html>error</html>'),
      geo: () => new Response('nope', { status: 403 }),
      // Fails once, then answers: the retry recovers it.
      galileo: () =>
        calls.filter((group) => group === 'galileo').length === 1
          ? Promise.reject(new TypeError('fetch failed'))
          : new Response(tle),
    };
    const failed = await mirror(dir, {
      groups: ['stations', 'visual', 'geo', 'galileo'],
      retryDelayMs: 0,
      fetchImpl: async (url) => {
        const group = new URL(url).searchParams.get('GROUP');
        calls.push(group);
        return responses[group]();
      },
    });
    assert.deepEqual(failed, [
      'visual: no TLE lines in the response',
      'geo: HTTP 403',
    ]);
    assert.equal(fs.readFileSync(path.join(dir, 'stations.txt'), 'utf8'), tle);
    assert.equal(fs.readFileSync(path.join(dir, 'galileo.txt'), 'utf8'), tle);
    assert.deepEqual(calls, ['stations', 'visual', 'visual', 'geo', 'geo', 'galileo', 'galileo']);
    assert.equal(fs.readFileSync(path.join(dir, 'visual.txt'), 'utf8'), 'previous visual\n');
    assert.ok(!fs.existsSync(path.join(dir, 'geo.txt')));
    assert.ok(hasTle(tle) && !hasTle('<html>error</html>'));
  } finally {
    fs.rmSync(dir, { recursive: true, force: true });
  }
});

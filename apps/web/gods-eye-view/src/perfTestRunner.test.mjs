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
  mkdirSync,
  readFileSync,
  rmSync,
  writeFileSync,
} from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import {
  discoverPerfTestFiles,
  perfBudgetTestOptions,
  perfTestArgs,
  runPerfTests,
} from '../scripts/run-perf-tests.mjs';

test('timing assertions are skipped with an actionable message unless explicitly enabled', () => {
  for (const env of [
    {},
    { GEV_PERF_BUDGETS: '0' },
    { GEV_PERF_BUDGETS: 'true' },
  ])
    assert.match(
      perfBudgetTestOptions(env).skip,
      /Timing budgets are opt-in; run npm run test:perf/,
    );
  assert.deepEqual(perfBudgetTestOptions({ GEV_PERF_BUDGETS: '1' }), {
    skip: false,
  });
});

test('test:perf discovers every benchmark and enables timing budgets in a serial process', (t) => {
  const root = mkdtempSync(path.join(tmpdir(), 'gev-perf-runner-'));
  t.after(() => rmSync(root, { recursive: true, force: true }));
  const expected = [
    'server/providers/example/provider.perf.test.mjs',
    'src/layers/anotherLayer/model.perf.test.mjs',
    'src/layers/wildlifeSightings/model.perf.test.mjs',
  ];
  for (const file of [
    ...expected,
    'src/layers/anotherLayer/functional.test.mjs',
  ]) {
    mkdirSync(path.dirname(path.join(root, file)), { recursive: true });
    writeFileSync(path.join(root, file), '');
  }
  assert.deepEqual(discoverPerfTestFiles(root), expected);
  const calls = [];
  const run = (...args) => {
    calls.push(args);
    return { status: 7 };
  };
  assert.equal(
    runPerfTests({
      root,
      env: { GEV_PERF_BUDGETS: '0', SENTINEL: 'kept' },
      run,
    }),
    7,
  );
  assert.equal(calls.length, 1);
  const [command, args, options] = calls[0];
  assert.equal(command, process.execPath);
  assert.deepEqual(args, perfTestArgs(expected));
  assert.ok(args.includes('--test-concurrency=1'));
  assert.ok(args.includes('--test-isolation=none'));
  assert.equal(options.cwd, root);
  assert.equal(options.env.GEV_PERF_BUDGETS, '1');
  assert.equal(options.env.SENTINEL, 'kept');
  assert.throws(
    () =>
      runPerfTests({ root, run: () => ({ error: new Error('spawn failed') }) }),
    /spawn failed/,
  );
  const pkg = JSON.parse(
    readFileSync(new URL('../package.json', import.meta.url), 'utf8'),
  );
  assert.equal(pkg.scripts['test:perf'], 'node scripts/run-perf-tests.mjs');
});

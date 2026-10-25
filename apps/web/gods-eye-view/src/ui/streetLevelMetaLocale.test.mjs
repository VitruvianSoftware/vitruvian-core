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

// The Street Level meta-line test must not depend on the system locale: the
// code formats the count in the app language (formatNumber), so a contributor
// whose terminal sets LANG=de_DE or es_ES must see the same green run as CI's
// C.UTF-8. Runs the presentation test file under three process locales.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const here = path.dirname(fileURLToPath(import.meta.url));
const target = path.join(here, 'streetLevelPresentation.test.mjs');

for (const locale of ['de_DE.UTF-8', 'es_ES.UTF-8', 'C.UTF-8']) {
  test(`streetLevelPresentation tests pass under LC_ALL=${locale}`, () => {
    // Drop the node:test child markers so the nested run is a real top-level run.
    const env = { ...process.env, LC_ALL: locale, LANG: locale };
    delete env.NODE_TEST_CONTEXT;
    delete env.NODE_TEST_WORKER_ID;
    const result = spawnSync(process.execPath, ['--test', target], {
      encoding: 'utf8',
      env,
    });
    const failed = result.stdout.match(/^ℹ fail (\d+)/m)?.[1] ?? '?';
    assert.equal(
      result.status,
      0,
      `exit status ${result.status}, ${failed} failing test(s) under ${locale}\n${result.stdout.slice(-700)}`,
    );
  });
}

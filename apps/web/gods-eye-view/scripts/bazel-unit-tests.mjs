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

/**
 * Bazel entry point for the upstream unit-test runner (monorepo-only file).
 *
 * rules_js puts a `node` shim on PATH that only works with the launcher's
 * JS_BINARY__NODE_BINARY variable. Several upstream tests spawn the dev
 * launcher shell scripts with a freshly built env that carries PATH but not
 * that variable, so `node` inside those scripts dies with "unbound variable".
 * Put a self-contained `node` launcher (real binary + the same fs patches)
 * ahead of the shim on PATH, then hand over to scripts/run-unit-tests.mjs.
 */
import { mkdtempSync, writeFileSync } from 'node:fs';
import os from 'node:os';
import path from 'node:path';

// process.execPath is the shim under rules_js, so read the launcher's variables.
const realNode = process.env.JS_BINARY__NODE_BINARY;
if (realNode) {
  const patches = process.env.JS_BINARY__NODE_PATCHES;
  const binDir = mkdtempSync(path.join(process.env.TEST_TMPDIR || os.tmpdir(), 'gev-node-'));
  const requirePatches = patches ? `--require ${JSON.stringify(patches)} ` : '';
  writeFileSync(
    path.join(binDir, 'node'),
    // --preserve-symlinks-main matches the rules_js launcher: a script run
    // through its runfiles symlink sees that path as import.meta.url, so
    // upstream's "invoked directly" guards (argv[1] === import.meta.url) hold.
    `#!/usr/bin/env bash\nexec ${JSON.stringify(realNode)} --preserve-symlinks-main ${requirePatches}"$@"\n`,
    { mode: 0o755 },
  );
  process.env.PATH = `${binDir}${path.delimiter}${process.env.PATH || ''}`;
}

const { runUnitTests } = await import('./run-unit-tests.mjs');
process.exitCode = runUnitTests();

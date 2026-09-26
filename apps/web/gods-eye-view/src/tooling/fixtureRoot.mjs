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

import { mkdtemp, realpath } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';

/**
 * Create a temporary directory for a test fixture, resolved to its physical
 * path.
 *
 * The system temp directory is reached through a symlink on macOS
 * (`/var` -> `/private/var`, `/tmp` -> `/private/tmp`). A test that gives the
 * logical path to something that reports paths back — a launched process's
 * working directory, a bundler's project root — then compares two spellings of
 * the same directory and fails. Resolving the root once, here, keeps both sides
 * on the physical path.
 *
 * @param {string} prefix - Directory name prefix, e.g. `gev-preview-`.
 * @returns {Promise<string>} The fixture root, with no symlinked component.
 */
export async function makeFixtureRoot(prefix) {
  return realpath(await mkdtemp(path.join(tmpdir(), prefix)));
}

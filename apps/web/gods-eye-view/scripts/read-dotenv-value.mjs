#!/usr/bin/env node
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

import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { loadEnv } from 'vite';

/**
 * Read one dotenv key with Vite's parser; no file content is executed.
 *
 * Reports what the FILES say. `loadEnv` lets `process.env` override the parsed
 * files, so an inherited export — an empty one above all, which is how a shell
 * says "unset" to this script's callers — would otherwise mask the value the
 * user wrote down. The key is hidden for the duration of the read and restored
 * afterwards, leaving the caller's environment untouched.
 */
export function readDotenvValue(variableName, rootDir = process.cwd(), mode = 'development') {
  const key = String(variableName || '').trim();
  if (!/^[A-Z_][A-Z0-9_]*$/i.test(key)) return '';
  const inherited = Object.prototype.hasOwnProperty.call(process.env, key)
    ? process.env[key]
    : undefined;
  if (inherited !== undefined) delete process.env[key];
  try {
    const env = loadEnv(mode, path.resolve(rootDir), '');
    return String(env[key] ?? '');
  } finally {
    if (inherited !== undefined) process.env[key] = inherited;
  }
}

const invokedPath = process.argv[1] ? path.resolve(process.argv[1]) : '';
if (invokedPath === fileURLToPath(import.meta.url)) {
  process.stdout.write(readDotenvValue(process.argv[2], process.argv[3] || process.cwd()));
}

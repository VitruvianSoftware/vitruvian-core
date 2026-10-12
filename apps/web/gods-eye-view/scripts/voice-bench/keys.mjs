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
 * Runtime key lookup for the voice benchmark. Keys are read from the
 * environment, then the macOS Keychain, at call time. They are never written
 * to results, logs, or files.
 */
import { execFileSync } from 'node:child_process';

const KEYCHAIN = {
  openai: { env: 'OPENAI_API_KEY', service: 'openai-api', account: 'api-key' },
  gemini: { env: 'GEMINI_API_KEY', service: 'gemini-api', account: 'api-key' },
};

const cache = new Map();

/** Resolve a provider key from the environment, then the Keychain. */
export function providerKey(provider) {
  if (cache.has(provider)) return cache.get(provider);
  const spec = KEYCHAIN[provider];
  if (!spec) throw new Error(`unknown key provider: ${provider}`);
  let value = process.env[spec.env] || '';
  if (!value && process.platform === 'darwin') {
    try {
      value = execFileSync(
        'security',
        ['find-generic-password', '-s', spec.service, '-a', spec.account, '-w'],
        { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] },
      ).trim();
    } catch {
      value = '';
    }
  }
  if (!value) throw new Error(`${spec.env} is not available (env or Keychain)`);
  cache.set(provider, value);
  return value;
}

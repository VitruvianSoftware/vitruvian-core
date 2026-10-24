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
 * Directories the app writes to while it runs. None is source, and none
 * should reload anything.
 */
const RUNTIME_WRITE_GLOBS = Object.freeze([
  '**/.gev-cache/**',
  '**/.gev-logs/**',
]);

/**
 * Keep the directories the app writes to out of the dev server's file watcher.
 *
 * Disk-cached providers write a file per response into `.gev-cache`, and the
 * voice debug log appends to `.gev-logs`. Left watched, each write costs the
 * watcher stat calls on libuv's thread pool, which `getaddrinfo` shares; heavy
 * cache writes have been seen to delay upstream DNS lookups.
 *
 * @returns {import('vite').Plugin} Config-only plugin; no server hooks.
 */
export function unwatchedRuntimeDirsPlugin() {
  return {
    name: 'gev-unwatched-runtime-dirs',
    apply: 'serve',
    config: () => ({
      server: { watch: { ignored: [...RUNTIME_WRITE_GLOBS] } },
    }),
  };
}

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
 * Boots server.mjs from a directory laid out the way the Dockerfile's runtime
 * stage lays out /app, then exercises the Street Level routes.
 *
 * server.mjs imports upstream's tile engine, so the image must carry every file
 * that engine imports. An upstream sync can add one; the server then fails to
 * start here, naming the missing file, before it fails in production.
 */
import { after, before, test } from 'node:test';
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import fs from 'node:fs';
import net from 'node:net';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const APP = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..');

/** The runtime stage's COPY lines that copy from the build context. */
function runtimeCopies(dockerfile) {
  const lines = dockerfile.split('\n').map((line) => line.trim());
  const start = lines.findIndex((line) => /^FROM\s+\S+\s+AS\s+runtime$/i.test(line));
  assert.ok(start >= 0, 'the Dockerfile has a runtime stage');
  const copies = [];
  for (const line of lines.slice(start + 1)) {
    if (/^FROM\s/i.test(line)) break;
    const match = /^COPY\s+(.+)$/i.exec(line);
    if (!match || /--from=/.test(match[1])) continue;
    const parts = match[1].split(/\s+/);
    copies.push({ sources: parts.slice(0, -1), dest: parts.at(-1) });
  }
  return copies;
}

/**
 * Copies file contents, never links: Node resolves a linked module's imports
 * from its real path, which here is the full source tree, so a link would hide
 * a file the image lacks.
 */
function copyTree(from, into) {
  if (!fs.statSync(from).isDirectory()) {
    fs.mkdirSync(path.dirname(into), { recursive: true });
    fs.copyFileSync(from, into);
    return;
  }
  for (const entry of fs.readdirSync(from)) {
    copyTree(path.join(from, entry), path.join(into, entry));
  }
}

/** Lays out `root` as the runtime stage lays out /app, without dist/. */
function layOutImage(root) {
  const dockerfile = fs.readFileSync(path.join(APP, 'Dockerfile'), 'utf8');
  for (const { sources, dest } of runtimeCopies(dockerfile)) {
    for (const source of sources) {
      const from = path.join(APP, source);
      const into = path.join(root, dest);
      const isFileIntoDir = !fs.statSync(from).isDirectory() && dest.endsWith('/');
      copyTree(from, isFileIntoDir ? path.join(into, path.basename(source)) : into);
    }
  }
  // The image installs package.json's dependencies; this package's own
  // node_modules holds the same set.
  fs.symlinkSync(path.join(APP, 'node_modules'), path.join(root, 'node_modules'), 'dir');
}

function freePort() {
  return new Promise((resolve, reject) => {
    const probe = net.createServer();
    probe.once('error', reject);
    probe.listen(0, '127.0.0.1', () => {
      const { port } = probe.address();
      probe.close(() => resolve(port));
    });
  });
}

// Under Bazel, process.execPath is the rules_js shim, which needs the
// launcher's variables; run the real binary, without the launcher's fs
// patches, as the image runs plain node.
const NODE = process.env.JS_BINARY__NODE_BINARY || process.execPath;

/** Starts server.mjs in `root` and resolves once /healthz answers. */
async function startServer(root, env) {
  const port = await freePort();
  const child = spawn(NODE, ['server.mjs'], {
    cwd: root,
    env: {
      PATH: process.env.PATH,
      NODE_ENV: 'production',
      HOST: '127.0.0.1',
      PORT: String(port),
      ...env,
    },
    stdio: ['ignore', 'pipe', 'pipe'],
  });
  let output = '';
  child.stdout.on('data', (chunk) => (output += chunk));
  child.stderr.on('data', (chunk) => (output += chunk));
  const exited = new Promise((resolve) => child.once('exit', resolve));
  const base = `http://127.0.0.1:${port}`;
  const deadline = Date.now() + 15_000;
  while (Date.now() < deadline) {
    if (child.exitCode !== null) break;
    try {
      const response = await fetch(`${base}/healthz`);
      if (response.ok) return { base, stop: () => (child.kill(), exited) };
    } catch {
      // Not listening yet.
    }
    await new Promise((resolve) => setTimeout(resolve, 100));
  }
  child.kill();
  await exited;
  assert.fail(`server.mjs did not start from the image layout:\n${output}`);
}

let root;
let keyless;
let keyed;

before(async () => {
  root = fs.mkdtempSync(path.join(os.tmpdir(), 'gev-image-'));
  layOutImage(root);
  keyless = await startServer(root, {
    GEV_RATELIMIT_MAPILLARY_PER_MIN: '3',
    GEV_RATELIMIT_OPENAI_PER_MIN: '3',
  });
  keyed = await startServer(root, { MAPILLARY_CLIENT_TOKEN: 'MLY|0|image-test' });
});

after(async () => {
  await keyless?.stop();
  await keyed?.stop();
  if (root) fs.rmSync(root, { recursive: true, force: true });
});

test('the status route says whether a token is configured', async () => {
  for (const [server, configured] of [
    [keyless, false],
    [keyed, true],
  ]) {
    const response = await fetch(`${server.base}/api/mapillary/status`);
    assert.equal(response.status, 200);
    assert.equal(response.headers.get('cache-control'), 'no-store');
    assert.deepEqual(await response.json(), { configured });
  }
  const post = await fetch(`${keyed.base}/api/mapillary/status`, { method: 'POST' });
  assert.equal(post.status, 405);
});

test('the tile route refuses bad requests before contacting Mapillary', async () => {
  const wrongLayer = await fetch(`${keyed.base}/api/mapillary/tiles/image/14/2/3`);
  assert.equal(wrongLayer.status, 400);
  assert.match((await wrongLayer.json()).error, /coverage/);
  const post = await fetch(`${keyed.base}/api/mapillary/tiles/coverage/14/2/3`, { method: 'POST' });
  assert.equal(post.status, 405);
});

test('without a token the tile route answers no_key, then its own rate limit', async () => {
  for (let i = 0; i < 3; i += 1) {
    const response = await fetch(`${keyless.base}/api/mapillary/tiles/coverage/14/2/3`);
    assert.equal(response.status, 503);
    assert.deepEqual(await response.json(), { error: 'no_key', keyRequired: true });
  }
  const limited = await fetch(`${keyless.base}/api/mapillary/tiles/coverage/14/2/3`);
  assert.equal(limited.status, 429);
  // Tiles count in a bucket of their own: the client's OpenAI allowance,
  // also 3 a minute here, is untouched.
  const summary = await fetch(`${keyless.base}/api/openai/hud-summary`);
  assert.equal(summary.status, 200);
});

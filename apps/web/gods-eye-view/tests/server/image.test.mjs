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
 * stage lays out /app, then checks that it serves upstream's routes the way
 * `vite preview` does: every route upstream mounts for preview, none of the
 * dev-only ones, and the same-site gate on the paid ones.
 *
 * The image must carry every file upstream's handlers import, so a file the
 * Dockerfile leaves out fails the server's start here, naming it. Outbound
 * network is stubbed in the server (no-network.mjs), so answers come from this
 * server alone.
 */
import { after, before, test } from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync, spawn } from 'node:child_process';
import fs from 'node:fs';
import http from 'node:http';
import { builtinModules } from 'node:module';
import net from 'node:net';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const APP = path.resolve(HERE, '..', '..');
const NO_NETWORK = pathToFileURL(path.join(HERE, 'no-network.mjs')).href;

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
  const child = spawn(NODE, ['--import', NO_NETWORK, 'server.mjs'], {
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
  const deadline = Date.now() + 30_000;
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

/**
 * The routes upstream's plugins mount under `vite preview` and under its dev
 * server, read in a child process from the image layout (installing the
 * plugins starts timers the child's exit clears).
 */
function upstreamRoutes(root) {
  const script = `
    import { EventEmitter } from 'node:events';
    const { localProviderPlugins } = await import('./server/providers/local.js');
    const { standaloneVoiceTools } = await import('./server/standalone/voiceTools.js');
    const record = (isPreview) => {
      const routes = new Set();
      const server = {
        middlewares: { use: (route) => typeof route === 'string' && routes.add(route) },
        httpServer: new EventEmitter(),
      };
      const env = { command: 'serve', mode: isPreview ? 'production' : 'development', isPreview };
      for (const plugin of localProviderPlugins({ realtime: { tools: standaloneVoiceTools() } })) {
        const applies = typeof plugin.apply === 'function'
          ? plugin.apply({}, env)
          : plugin.apply === undefined || plugin.apply === 'serve';
        if (applies) plugin[isPreview ? 'configurePreviewServer' : 'configureServer']?.(server);
      }
      return [...routes].sort();
    };
    process.stdout.write(JSON.stringify({ preview: record(true), dev: record(false) }));
    process.exit(0);
  `;
  const out = execFileSync(NODE, ['--import', NO_NETWORK, '--input-type=module', '-e', script], {
    cwd: root,
    env: { PATH: process.env.PATH },
    encoding: 'utf8',
  });
  return JSON.parse(out);
}

/** Whether a response is upstream's answer for an /api path nothing mounts. */
async function isUnknownApiRoute(response) {
  if (response.status !== 404) return false;
  const body = await response.json().catch(() => ({}));
  return body.error === 'Unknown API route';
}

/**
 * The packages the server's import graph reaches from server.mjs: bare
 * specifiers of every static or literal dynamic import, and of every literal
 * require(), createRequire(...)('x') included, following relative ones through
 * the image layout.
 */
function importedPackages(root) {
  const statement = new RegExp(
    [
      String.raw`(?:^|[\s;])(?:import|export)\b[^'"\x60;]*?\bfrom\s*['"]([^'"]+)['"]`,
      String.raw`(?:^|[\s;(,=])import\s*['"]([^'"]+)['"]`,
      String.raw`import\(\s*['"]([^'"]+)['"]\s*\)`,
      // require('x'), and createRequire(import.meta.url)('x').
      String.raw`(?:\brequire|\))\(\s*['"]([^'"]+)['"]\s*\)`,
    ].join('|'),
    'gm',
  );
  const packages = new Set();
  const seen = new Set();
  const todo = [path.join(root, 'server.mjs')];
  while (todo.length) {
    const file = todo.pop();
    if (seen.has(file)) continue;
    seen.add(file);
    const source = fs.readFileSync(file, 'utf8').replace(/\/\*[\s\S]*?\*\//g, '');
    for (const match of source.matchAll(statement)) {
      const specifier = match[1] || match[2] || match[3] || match[4];
      if (specifier.startsWith('.')) {
        const target = path.resolve(path.dirname(file), specifier);
        const found = [target, `${target}.js`, `${target}.mjs`].find(
          (candidate) => fs.existsSync(candidate) && fs.statSync(candidate).isFile(),
        );
        if (found) todo.push(found);
      } else if (!specifier.startsWith('node:') && !builtinModules.includes(specifier.split('/')[0])) {
        const parts = specifier.split('/');
        packages.add(specifier.startsWith('@') ? parts.slice(0, 2).join('/') : parts[0]);
      }
    }
  }
  return packages;
}

const MIRROR_TLE =
  'ISS (ZARYA)\n1 25544U 98067A   26280.50000000  .00010000  00000-0  18000-3 0  9990\n2 25544  51.6400 100.0000 0005000 100.0000 260.0000 15.50000000400000\n';

/** A TLE mirror on loopback that holds only stations.txt. */
async function startMirror() {
  const mirror = http.createServer((req, res) => {
    if (req.url === '/tle/stations.txt') {
      res.writeHead(200, { 'Content-Type': 'text/plain' });
      res.end(MIRROR_TLE);
      return;
    }
    res.writeHead(404);
    res.end('not found');
  });
  await new Promise((resolve) => mirror.listen(0, '127.0.0.1', resolve));
  return {
    url: `http://127.0.0.1:${mirror.address().port}/tle/`,
    stop: () => new Promise((resolve) => mirror.close(resolve)),
  };
}

let root;
let routes;
let keyless;
let keyed;
let tleMirror;

before(async () => {
  root = fs.mkdtempSync(path.join(os.tmpdir(), 'gev-image-'));
  layOutImage(root);
  routes = upstreamRoutes(root);
  tleMirror = await startMirror();
  keyless = await startServer(root, { CELESTRAK_TLE_MIRROR_URL: tleMirror.url });
  keyed = await startServer(root, { MAPILLARY_CLIENT_TOKEN: 'MLY|0|image-test' });
});

after(async () => {
  await keyless?.stop();
  await keyed?.stop();
  await tleMirror?.stop();
  if (root) fs.rmSync(root, { recursive: true, force: true });
});

test('the server imports only runtime dependencies', () => {
  // The image installs package.json's dependencies alone; this package's
  // node_modules, which the server runs on here, has the devDependencies too.
  const { dependencies } = JSON.parse(fs.readFileSync(path.join(root, 'package.json'), 'utf8'));
  const devOnly = [...importedPackages(root)].filter((name) => !(name in dependencies));
  assert.deepEqual(devOnly, [], 'imported by the server but not in dependencies');
});

test('every route upstream mounts for preview is served', async () => {
  // The client's live layers, so a regression names the feature it breaks.
  for (const route of ['/api/flights', '/api/military', '/api/vessels', '/api/geocode']) {
    assert.ok(routes.preview.includes(route), `upstream mounts ${route}`);
  }
  // A route is missing when it gets the answer a path nothing mounts gets.
  // Some routes serve only paths below them and 404 their own, so compare the
  // error, not just the status.
  const unmounted = await (await fetch(`${keyless.base}/api/no-such-route`)).json();
  assert.ok(unmounted.error, 'an unmounted /api path answers a JSON error');
  const missing = [];
  for (const route of routes.preview) {
    const response = await fetch(`${keyless.base}${route}`);
    const body = await response.json().catch(() => ({}));
    if (response.status === 404 && body.error === unmounted.error) missing.push(route);
  }
  assert.deepEqual(missing, [], 'routes upstream mounts that server.mjs does not serve');
});

test('dev-only routes stay out of production', async () => {
  // Upstream's credential panel writes keys to disk; it installs in its dev
  // server only. A new dev-only route lands here for a decision.
  const devOnly = routes.dev.filter((route) => !routes.preview.includes(route));
  assert.deepEqual(devOnly, ['/api/setup/keys', '/api/setup/status']);
  for (const route of devOnly) {
    for (const method of ['GET', 'POST']) {
      const response = await fetch(`${keyless.base}${route}`, {
        method,
        headers: { 'Content-Type': 'application/json' },
        body: method === 'POST' ? '{"GOOGLE_MAPS_API_KEY":"x"}' : undefined,
      });
      assert.ok(await isUnknownApiRoute(response), `${method} ${route} is not served`);
    }
  }
});

test('an unknown API path answers 404 JSON, not the app', async () => {
  const response = await fetch(`${keyless.base}/api/does-not-exist`);
  assert.ok(await isUnknownApiRoute(response));
});

test('the paid routes refuse requests a proxy forwarded', async () => {
  for (const route of [
    '/api/mapillary/status',
    '/api/mapillary/tiles/coverage/14/2/3',
    '/api/openai/hud-summary',
    '/api/google/nearby-places',
    '/api/google/text-search',
    '/api/realtime/token',
  ]) {
    const response = await fetch(`${keyed.base}${route}`, {
      headers: { 'X-Forwarded-For': '203.0.113.7' },
    });
    assert.equal(response.status, 403, route);
  }
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
  const keylessTile = await fetch(`${keyless.base}/api/mapillary/tiles/coverage/14/2/3`);
  assert.equal(keylessTile.status, 503);
  assert.deepEqual(await keylessTile.json(), { error: 'no_key', keyRequired: true });
});

test('Celestrak groups come from the TLE mirror, then CelesTrak', async () => {
  const mirrored = await fetch(`${keyless.base}/api/celestrak/stations`);
  assert.equal(mirrored.status, 200);
  assert.equal(await mirrored.text(), MIRROR_TLE);
  // The mirror lacks this group, so the server falls back to CelesTrak, which
  // no-network.mjs refuses, and answers 502 with nothing cached.
  const unmirrored = await fetch(`${keyless.base}/api/celestrak/visual`);
  assert.equal(unmirrored.status, 502);
  // Without a mirror configured, CelesTrak is the only source. (Both servers
  // share the layout's cache, so this asks for a group neither has cached.)
  const direct = await fetch(`${keyed.base}/api/celestrak/geo`);
  assert.equal(direct.status, 502);
});

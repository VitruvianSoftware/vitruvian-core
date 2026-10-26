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

import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';
import {
  defaultGatewayFromRouteTable,
  unwritableRootWarning,
  resolveTrustedPeers,
} from '../scripts/docker-start.mjs';

// The shape of /proc/net/route inside a bridge-networked container:
// little-endian hex addresses, the default route first, an interface route
// after.
const BRIDGE_ROUTES = [
  'Iface\tDestination\tGateway \tFlags\tRefCnt\tUse\tMetric\tMask\t\tMTU\tWindow\tIRTT',
  'eth0\t00000000\t0100A8C0\t0003\t0\t0\t0\t00000000\t0\t0\t0',
  'eth0\t0000A8C0\t00000000\t0001\t0\t0\t0\t00F0FFFF\t0\t0\t0',
  '',
].join('\n');

test('the container gateway is decoded from the kernel routing table', () => {
  assert.equal(defaultGatewayFromRouteTable(BRIDGE_ROUTES), '192.168.0.1', 'little-endian hex, default route only');
  assert.equal(
    defaultGatewayFromRouteTable(BRIDGE_ROUTES.replace('0100A8C0', '011FAC')),
    null,
    'a malformed gateway field is not an address',
  );
  assert.equal(
    defaultGatewayFromRouteTable(BRIDGE_ROUTES.replace('\t0003\t', '\t0002\t')),
    null,
    'a default route that is not up is ignored',
  );
  assert.equal(
    defaultGatewayFromRouteTable(BRIDGE_ROUTES.replace('0100A8C0', '00000000')),
    null,
    'a zero gateway is not an address',
  );
  assert.equal(
    defaultGatewayFromRouteTable(
      BRIDGE_ROUTES.split('\n').filter((line) => !line.includes('00000000\t0100A8C0')).join('\n'),
    ),
    null,
    '--network none has no default route and must not invent one',
  );
  assert.equal(defaultGatewayFromRouteTable(''), null);
  assert.equal(defaultGatewayFromRouteTable(undefined), null);
});

test('an operator list wins, and no gateway trusts nothing', () => {
  assert.equal(resolveTrustedPeers({ env: {}, routeTable: BRIDGE_ROUTES }), '192.168.0.1');
  assert.equal(resolveTrustedPeers({ env: { GEV_KEY_SETUP_TRUSTED_PEERS: ' 10.9.8.7 ' }, routeTable: BRIDGE_ROUTES }), '10.9.8.7');
  assert.equal(
    resolveTrustedPeers({ env: { GEV_KEY_SETUP_TRUSTED_PEERS: '  ' }, routeTable: BRIDGE_ROUTES }),
    '192.168.0.1',
    'a blank override falls through to the gateway',
  );
  assert.equal(resolveTrustedPeers({ env: {}, routeTable: '' }), '', 'loopback-only when there is no gateway');
});

test('an unwritable checkout is named at start instead of failing quietly', () => {
  const ids = { owner: { uid: 0, gid: 0 }, runAs: { uid: 1000, gid: 1000 } };
  assert.equal(unwritableRootWarning({ root: '/app', writable: true, ...ids }), null, 'a writable checkout says nothing');
  const warning = unwritableRootWarning({ root: '/app', writable: false, ...ids });
  assert.match(warning, /owned by 0:0/, 'names the owner');
  assert.match(warning, /runs as 1000:1000/, 'names the ids the container runs as');
  assert.match(warning, /chown -R 1000:1000/, 'offers handing the checkout to the container user first');
  assert.match(warning, /env UID=0 GID=0 docker compose up/, 'or the env form, which bash does not ignore');
});

test('the Docker install path keeps its loopback-only, launcher-owned contract', () => {
  const dockerfile = readFileSync(new URL('../Dockerfile', import.meta.url), 'utf8');
  // This copy's image is the production server (server.mjs), not upstream's dev container.
  assert.match(dockerfile, /^CMD \["node", "server\.mjs"\]$/m, 'the production server is the container entry point');

  const compose = readFileSync(new URL('../compose.yaml', import.meta.url), 'utf8');
  assert.match(compose, /^\s+- "127\.0\.0\.1:4173:4173"$/m, 'the port is published on the host loopback only');
  assert.match(compose, /^\s+- GEV_KEY_SETUP_TRUSTED_PEERS$/m, 'the operator policy reaches the launcher without a hard-coded address');
  assert.match(compose, /^\s+- GEV_ALLOWED_HOSTS$/m, 'the host allowlist reaches Vite');
  assert.doesNotMatch(compose, /network_mode/, 'the container keeps its own network namespace');
  assert.match(compose, /^\s+- \.:\/app:z$/m, 'SELinux hosts can read the bind-mounted checkout');
});

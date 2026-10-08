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
 * Mirrors the CelesTrak groups the app requests, for a server CelesTrak does
 * not answer. Connections from the homelab to celestrak.org time out (CelesTrak
 * throttles hosts that poll it too often, as the old uncached server did), so
 * .github/workflows/gods-eye-view-tle-mirror.yaml runs this every 6 hours from
 * GitHub's runners and publishes the files on the gods-eye-view-tle branch;
 * the server reads them through CELESTRAK_TLE_MIRROR_URL
 * (server/providers/space/celestrak.js) and falls back to CelesTrak.
 *
 *   node apps/web/gods-eye-view/tle-mirror/mirror.mjs <dir>
 *
 * writes <dir>/<group>.txt for each group it fetches, and leaves the file a
 * failed group already had, so one bad fetch never empties the mirror.
 */
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

/**
 * The groups the client requests: the satellite catalog's (CATALOG_GROUPS in
 * src/layers/satellites/policy.js), the space tool's (GROUPS in
 * src/tools/queries/space.js) and the launches layer's (`active`).
 * mirror.test.mjs holds this list to the client's code.
 */
export const MIRRORED_GROUPS = Object.freeze([
  'active',
  'stations',
  'visual',
  'gps-ops',
  'glo-ops',
  'galileo',
  'geo',
  'starlink',
]);

// CelesTrak 403s bulk groups (`active`) without a descriptive User-Agent.
const USER_AGENT =
  'vitruvian-core-gods-eye-view-tle-mirror/1.0 (+https://github.com/VitruvianSoftware/vitruvian-core)';

/** CelesTrak's URL for a group, as celestrakTleUrl builds it. */
export function celestrakGroupUrl(group) {
  const url = new URL('https://celestrak.org/NORAD/elements/gp.php');
  url.searchParams.set('GROUP', group);
  url.searchParams.set('FORMAT', 'tle');
  return url.toString();
}

/** Whether a body holds TLEs; an error page holds none. */
export function hasTle(body) {
  return /^1 /m.test(body) && /^2 /m.test(body);
}

async function fetchGroup(group, fetchImpl) {
  const response = await fetchImpl(celestrakGroupUrl(group), {
    headers: { 'User-Agent': USER_AGENT },
    signal: AbortSignal.timeout(60_000),
  });
  if (!response.ok) throw new Error(`HTTP ${response.status}`);
  const body = await response.text();
  if (!hasTle(body)) throw new Error('no TLE lines in the response');
  return body;
}

/**
 * Fetches every group into `dir`, trying each twice. Returns `group: reason`
 * for each group that failed; their files, if any, are left as they were.
 */
export async function mirror(
  dir,
  { fetchImpl = fetch, groups = MIRRORED_GROUPS, retryDelayMs = 30_000 } = {},
) {
  fs.mkdirSync(dir, { recursive: true });
  const failed = [];
  for (const group of groups) {
    try {
      let body;
      try {
        body = await fetchGroup(group, fetchImpl);
      } catch {
        await new Promise((resolve) => setTimeout(resolve, retryDelayMs));
        body = await fetchGroup(group, fetchImpl);
      }
      fs.writeFileSync(path.join(dir, `${group}.txt`), body);
    } catch (error) {
      failed.push(`${group}: ${error.message}`);
    }
  }
  return failed;
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const dir = process.argv[2];
  if (!dir) {
    console.error('usage: mirror.mjs <dir>');
    process.exit(2);
  }
  const failed = await mirror(dir);
  for (const line of failed) console.error(`::warning::${line}`);
  // A partial refresh still publishes; only a total failure fails the run.
  if (failed.length === MIRRORED_GROUPS.length) process.exit(1);
}

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

export function isPinokioShareEnabled(value) {
  return /^(1|true)$/i.test(String(value || '').trim());
}

export function validatePinokioSharing(env = process.env) {
  const cloudflare = isPinokioShareEnabled(env.PINOKIO_SHARE_CLOUDFLARE);
  const local = isPinokioShareEnabled(env.PINOKIO_SHARE_LOCAL);
  const shareVariable = String(env.PINOKIO_SHARE_VAR || '').trim();
  if (cloudflare || local || shareVariable !== '__gev_sharing_disabled__') {
    throw new Error(
      'Pinokio sharing is unavailable because the current supported release can expose the app after child preflight '
      + 'and logs successful tunnel-login passcodes. Keep PINOKIO_SHARE_CLOUDFLARE=false, '
      + 'PINOKIO_SHARE_LOCAL=false, and PINOKIO_SHARE_VAR=__gev_sharing_disabled__.',
    );
  }
  return { cloudflare: false, local: false, protected: false };
}

function run() {
  validatePinokioSharing();
  console.log('[Pinokio] Local-only launch.');
}

const invokedPath = process.argv[1] ? path.resolve(process.argv[1]) : '';
if (invokedPath === fileURLToPath(import.meta.url)) {
  try {
    run();
  } catch (error) {
    console.error(`[Pinokio] ${error.message}`);
    process.exitCode = 1;
  }
}

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


import {
  LAYER_STATE_TOKEN_RESERVATIONS,
  nextLayerStateToken,
} from '../src/data/layerState.js';

const layerId = String(process.argv[2] || '').trim();

if (!/^[a-z0-9-]+$/.test(layerId)) {
  console.error('Usage: npm run layer-token:next -- <layer-id>');
  process.exitCode = 1;
} else if (Object.hasOwn(LAYER_STATE_TOKEN_RESERVATIONS, layerId)) {
  console.error(
    `${layerId} already owns token ${LAYER_STATE_TOKEN_RESERVATIONS[layerId]}`,
  );
  process.exitCode = 1;
} else {
  console.log(`${layerId}: ${nextLayerStateToken()}`);
  console.log('Order: free digits 0-9, then two-character base-36 00-zz.');
  console.log('Re-run after rebasing onto the latest main before merge.');
}

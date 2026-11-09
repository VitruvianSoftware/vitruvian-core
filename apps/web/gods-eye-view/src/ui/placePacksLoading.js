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
 * The place packs in the top-centre loading status: they load lazily, on the
 * Cockpit's first place lookup (`src/data/placeBelow.js`), so while one is on
 * its way the status names them beside the layers, and a pack that would not
 * load makes the batch end LOAD FAILED.
 */

import { placePacksStatus } from '../data/placeBelow.js';
import { LOADING_NAME_KEYS } from './layerNames.js';

/**
 * The data layers, with the place packs as one more entry while they load
 * or after one would not load, so a batch they join ends LOAD FAILED rather
 * than LOAD COMPLETE.
 */
export function withPlacePacks(
  layers,
  { loading, failed } = placePacksStatus(),
) {
  if (!loading && !failed) return layers;
  return [
    ...layers,
    {
      id: 'place-names',
      name: LOADING_NAME_KEYS['place-names'],
      enabled: true,
      stats: { loading, error: failed ? 'Place names did not load' : null },
    },
  ];
}

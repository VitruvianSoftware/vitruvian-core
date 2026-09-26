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

import { createVesselLayer } from '../../layers/vessels/index.js';
import * as context from '../../data/contextStore.js';
import * as trails from '../../data/trailRenderer.js';
import * as labels from '../../data/detectionDraw.js';
import * as picking from '../../data/pickRegistry.js';
import * as overlay from '../../overlays/worldOverlay.js';
import * as geoid from '../../data/geoid.js';
import * as sprites from '../../data/spriteOrder.js';
import * as focus from '../../data/focusDeemphasis.js';
import * as worldFocus from '../../worldFocus.js';
import * as render from '../../renderGovernor.js';

/** Construct one layer using the application scene owners and a supplied source. */
export function createApplicationVessels({ source, options = {} }) {
  return createVesselLayer({
    source,
    options,
    services: {
      context,
      trails,
      labels,
      picking,
      overlay,
      geoid,
      sprites,
      focus,
      worldFocus,
      render,
    },
  });
}

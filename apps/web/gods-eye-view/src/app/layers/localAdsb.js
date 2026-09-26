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

import { createLocalAdsbLayer } from '../../layers/localAdsb/index.js';
import { createLocalReceiverFeeds } from '../../layers/localAdsb/feeds.js';
import { SdrController } from '../../sdr/controller.js';
import * as render from '../../renderGovernor.js';
import * as context from '../../data/contextStore.js';
import * as picking from '../../data/pickRegistry.js';
import * as trails from '../../data/trailRenderer.js';
import * as geoid from '../../data/geoid.js';
import { markDetectionSourcesChanged } from '../../data/detection.js';
import { refreshTrackedReadout } from '../../data/trackedReadout.js';

/**
 * Construct the Local ADS-B layer, the browser RTL-SDR session it shares with
 * the Radio panel, and the decoder-feed session. Construction opens no device
 * and makes no request; the SDR starts only from an explicit Connect and the
 * feeds are polled only while the layer is enabled.
 *
 * `displayParams` reads the public Flights layer's DISPLAY-rail 3D preference
 * (`{ models3d, models3dMode }`) so local aircraft follow the same toggle;
 * `enrichment` is the Flights source whose cached adsbdb proxy they share.
 */
export function createApplicationLocalAdsb({
  receiver = new SdrController(),
  feeds = createLocalReceiverFeeds(),
  surface = null,
  enrichment = null,
  displayParams = null,
  resolveAsset = (url) =>
    `${import.meta.env?.BASE_URL || '/'}${url.replace(/^\//, '')}`,
} = {}) {
  return createLocalAdsbLayer({
    receiver,
    feeds,
    resolveAsset,
    services: {
      render,
      context,
      picking,
      trails,
      geoid,
      groundSnap: surface?.groundSnap || null,
      enrichment,
      display: displayParams ? { getParams: displayParams } : null,
      detection: { markSourcesChanged: markDetectionSourcesChanged },
      overlays: { refreshReadout: refreshTrackedReadout },
    },
  });
}

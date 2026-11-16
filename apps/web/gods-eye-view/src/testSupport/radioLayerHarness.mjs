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

import { radioLayer } from '../data/radio.js';
import { bindRenderer } from '../render/rendererOf.js';
import { bindFakeDraw } from './fakeDrawPort.mjs';
// The layer's clicks and floors take a viewer of the test's own, with no
// renderer bound: its factories load as `./render/cesium/unbound` loads them.
import '../render/cesium/unbound.js';

export function radioStationRow(overrides = {}) {
  return {
    id: '00000000-0000-4000-8000-000000000001',
    name: 'Station',
    lat: 30,
    lon: -97,
    streamUrl: 'https://radio.example.com/station.mp3',
    homepage: null,
    tags: ['news'],
    languages: ['English'],
    state: 'Texas',
    country: 'United States',
    countryCode: 'US',
    metadataTrust: 'untrusted-community',
    codec: 'MP3',
    bitrate: 128,
    ...overrides,
  };
}

/**
 * Run `body` against an enabled `radioLayer` that serves `stations`, drawing
 * through `renderer.draw`, or a fake draw port (with `renderer`'s other
 * ports, if given).
 * Streams listed in `failingUrls` (mutable) reject play(); `body` receives the
 * played URLs, the catalog, whose rows and generation the next update()
 * serves, and the fake draw port.
 */
export async function withRadioLayer(
  { stations, failingUrls = [], renderer = {} },
  body,
) {
  const originalFetch = globalThis.fetch;
  const originalAudio = globalThis.Audio;
  const playUrls = [];
  const catalog = { rows: stations, generation: 1 };
  globalThis.Audio = class FakeAudio {
    constructor() {
      this.volume = 0.8;
      this.src = '';
    }

    addEventListener() {}
    pause() {}
    play() {
      playUrls.push(this.src);
      if (failingUrls.includes(this.src)) {
        return Promise.reject(
          new DOMException('unavailable', 'NotSupportedError'),
        );
      }
      return Promise.resolve();
    }
    removeAttribute() {
      this.src = '';
    }
    load() {}
  };
  globalThis.fetch = async (url) =>
    String(url).startsWith('/api/radio/click/')
      ? { ok: true }
      : new Response(
          JSON.stringify({
            stations: catalog.rows,
            stale: false,
            degraded: false,
            acceptedGeneration: catalog.generation,
            catalogInstance: 'qa-instance-a',
            updatedAt: new Date().toISOString(),
          }),
          { status: 200, headers: { 'Content-Type': 'application/json' } },
        );
  const viewer = {
    camera: { positionWC: { x: 7_000_000, y: 0, z: 0 } },
    scene: {
      canvas: {
        disableRootEvents: true,
        onwheel: null,
        addEventListener() {},
        removeEventListener() {},
      },
    },
  };
  // The stations draw through the renderer's draw port: `renderer.draw`
  // when given, else a fake one.
  const { draw, unbind } = renderer.draw
    ? { draw: renderer.draw, unbind: bindRenderer(viewer, renderer) }
    : bindFakeDraw(viewer, renderer);
  radioLayer.destroy();
  try {
    radioLayer.init(viewer);
    radioLayer.enable();
    await radioLayer.update();
    await body({ playUrls, catalog, draw });
  } finally {
    globalThis.fetch = originalFetch;
    if (originalAudio === undefined) delete globalThis.Audio;
    else globalThis.Audio = originalAudio;
    radioLayer.destroy();
    unbind();
  }
}

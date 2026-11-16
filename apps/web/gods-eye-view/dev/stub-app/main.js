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
 * The whole application on the stub renderer (`src/render/stub`), with only
 * the contract's required members: the proof that the application runs on
 * those members alone, and needs no code that knows which renderer it is.
 * `scripts/qa-stub-boot.mjs` serves the application's page with this entry
 * in place of `src/main.js`, boots it headless, runs its data layers and
 * checks that no Cesium module loads.
 *
 * The stub runs nothing on its own: each animation frame here ticks it once.
 * `window.__stubBoot` exposes the application and the renderer it made.
 */
import { createStandaloneApplication } from '../../src/standalone/application.js';
import { createStubRendererPlugin } from '../../src/render/stub/index.js';

const renderers = [];

/** Tick a renderer once per animation frame until it is destroyed. */
function drive(renderer) {
  const step = () => {
    if (!renderers.includes(renderer)) return;
    renderer.testing.tick();
    requestAnimationFrame(step);
  };
  requestAnimationFrame(step);
}

// The required tier, no capability at all; `?capabilities=all` gives the
// stub every capability, to see what the layers draw with them.
const allCapabilities =
  new URLSearchParams(location.search).get('capabilities') === 'all';

const plugin = createStubRendererPlugin(
  allCapabilities ? {} : { capabilities: [] },
  (renderer) => {
    renderers.push(renderer);
    const destroy = renderer.destroy.bind(renderer);
    renderer.destroy = () => {
      renderers.splice(renderers.indexOf(renderer), 1);
      destroy();
    };
    drive(renderer);
  },
);

const application = createStandaloneApplication({
  renderer: plugin,
  allowQaRegistration: true,
});

window.__stubBoot = {
  application,
  renderers,
  started: application.start().then(
    () => ({ ok: true }),
    (error) => {
      console.error('Stub application failed to start:', error);
      return { ok: false, error: String(error?.stack || error) };
    },
  ),
};

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

/** Browser proof of Layers panel replacement and subscription ownership. */
import puppeteer from 'puppeteer';
const browser = await puppeteer.launch({
  headless: true,
  args: [
    '--no-sandbox',
    ...(process.platform === 'darwin'
      ? ['--use-angle=metal', '--enable-gpu']
      : ['--use-gl=angle', '--use-angle=swiftshader']),
  ],
});
const page = await browser.newPage();
let failures = 0;
const errors = [];
page.on('pageerror', (error) => errors.push(error.message));
const check = (name, passed) => {
  console.log(`[${passed ? 'PASS' : 'FAIL'}] ${name}`);
  if (!passed) failures++;
};
try {
  await page.goto(
    `${process.env.QA_BASE_URL || 'http://localhost:4173'}/?welcome=0`,
    { waitUntil: 'domcontentloaded' },
  );
  await page.waitForFunction(() => window.__godsEyeView?.dataManager, {
    timeout: 60000,
  });
  const results = await page.evaluate(async () => {
    const manager = window.__godsEyeView.dataManager;
    const entry = document.querySelector(
      'script[type="module"][src*="/src/main.js"]',
    );
    const { application } = await import(entry.src);
    const { presentation } = application.getComponents().data;
    const container = presentation.panel._toggleContainer;
    const id = 'qa-panel-lifecycle';
    let listener = null;
    let enabled = 0;
    window.__gevQaRegisterLayer(manager, {
      id,
      name: '<b>Literal layer</b>',
      icon: '◌',
      source: 'Local fixture',
      updateInterval: -1,
      init() {},
      enable() {
        enabled++;
      },
      disable() {},
      update() {},
      destroy() {},
      getStats: () => ({ count: 1250, lastUpdate: Date.now(), stale: true }),
      getRowControls: () => ({ chips: [] }),
      setRowControlsListener: (callback) => {
        listener = callback;
      },
    });
    const result = [];
    try {
      presentation.mount(container);
      const row = () => container.querySelector(`[data-layer-id="${id}"]`);
      const first = row().querySelector('.data-toggle-btn');
      result.push([
        'descriptor text is literal content',
        row().querySelector('.data-name').textContent ===
          '<b>Literal layer</b>' && !row().querySelector('b'),
      ]);
      result.push([
        'row subscription is installed',
        typeof listener === 'function',
      ]);
      presentation.mount(container);
      first.click();
      await Promise.resolve();
      result.push([
        'a detached row cannot issue an enable action',
        enabled === 0 && !manager.isEnabled(id),
      ]);
      await manager.setEnabled(id, true);
      result.push([
        'count is presented from the supplied snapshot',
        row().querySelector('.data-count').textContent === '1.3K',
      ]);
      result.push([
        'feed state reflects the settled layer snapshot',
        row().querySelector('.data-toggle-btn').dataset.feedState === 'stale',
      ]);
      const ui = window.__godsEyeView.styleManager;
      ui._clearSelectedLayersBtn.click();
      result.push([
        'native clear activation presents busy state',
        ui._clearSelectedLayersBtn.getAttribute('aria-busy') === 'true' &&
          !!ui._contextControls._clearSelectedLayersPromise,
      ]);
      await ui._contextControls._clearSelectedLayersPromise;
      result.push([
        'clear settles through the existing layer transaction',
        !manager.isEnabled(id) &&
          ui._clearSelectedLayersBtn.getAttribute('aria-busy') === 'false',
      ]);
      await manager.setEnabled(id, true);
      const final = row().querySelector('.data-toggle-btn');
      presentation._panel.destroy();
      final.click();
      await Promise.resolve();
      result.push([
        'destroyed panel releases row subscriptions',
        listener === null,
      ]);
      result.push([
        'destroyed controls cannot change the layer',
        manager.isEnabled(id),
      ]);
    } finally {
      presentation._panel?.destroy();
      presentation._panel = null;
      await window.__gevQaUnregisterLayer(manager, id);
      presentation.mount(container);
    }
    result.push([
      'ordinary layer rows return after reassembly',
      container.querySelectorAll('.data-toggle-row').length > 10,
    ]);
    return result;
  });
  for (const [name, passed] of results) check(name, passed);
  check('no uncaught browser errors', errors.length === 0);
} finally {
  await browser.close();
}
console.log(`RESULT: ${failures} failures`);
process.exitCode = failures ? 1 : 0;

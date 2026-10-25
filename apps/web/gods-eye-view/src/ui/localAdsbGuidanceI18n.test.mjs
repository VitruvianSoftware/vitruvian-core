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

import test from 'node:test';
import assert from 'node:assert/strict';

test('Local ADS-B guidance hint is translated in the layer row', async () => {
  const { setLocale, t } = await import('../i18n/index.js');
  const { LayerPanel } = await import('./layerPanel.js');
  const { localAdsbStatus } = await import('../layers/localAdsb/status.js');
  const english = localAdsbStatus({
    receiver: { webUsbSupported: true, connected: false },
    feedState: null,
    heard: 0,
  });
  assert.equal(
    LayerPanel.prototype._buildMetaText.call(LayerPanel.prototype, {
      id: 'local-adsb',
      enabled: true,
      lifecycleState: 'enabled',
      stats: { count: 0, lastUpdate: null, ...english },
    }),
    'RTL-SDR · WebUSB · connect a receiver in Radio',
  );
  for (const locale of ['es', 'ru']) {
    setLocale(locale);
    for (const receiver of [
      { webUsbSupported: true, connected: false },
      { webUsbSupported: false, connected: false },
      { webUsbSupported: true, connected: true, mode: 'fm' },
    ]) {
      const stats = localAdsbStatus({ receiver, feedState: null, heard: 0 });
      const text = LayerPanel.prototype._buildMetaText.call(
        LayerPanel.prototype,
        {
          id: 'local-adsb',
          enabled: true,
          lifecycleState: 'enabled',
          stats: { count: 0, lastUpdate: null, ...stats },
        },
      );
      assert.notEqual(
        t(stats.statusMessage),
        stats.statusMessage,
        `${locale}: no catalog entry for "${stats.statusMessage}"`,
      );
      assert.ok(
        !text.includes(stats.statusMessage),
        `${locale}: row shows English hint: ${text}`,
      );
    }
  }
  setLocale('en');
});

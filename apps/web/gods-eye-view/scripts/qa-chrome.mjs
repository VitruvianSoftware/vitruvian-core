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
 * The browser for gates that drive an installed Chrome. These gates were
 * written against macOS Google Chrome, which Windows and Linux do not have.
 */
import { existsSync } from 'node:fs';

export const MACOS_CHROME =
  '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';

/**
 * PUPPETEER_EXECUTABLE_PATH when set, then macOS Google Chrome when it is
 * installed. Otherwise undefined, so Puppeteer launches the browser it manages.
 */
export function chromeExecutablePath({
  env = process.env,
  exists = existsSync,
} = {}) {
  if (env.PUPPETEER_EXECUTABLE_PATH) return env.PUPPETEER_EXECUTABLE_PATH;
  return exists(MACOS_CHROME) ? MACOS_CHROME : undefined;
}

/** Restore an owned test window before capture: focus emulation alone does not
 * unminimize the native compositor, so CDP screenshots can otherwise stall. */
export async function captureQaScreenshot(
  page,
  options,
  { headful = true } = {},
) {
  if (headful) {
    const session = await page.createCDPSession();
    try {
      const { windowId, bounds } = await session.send(
        'Browser.getWindowForTarget',
      );
      if (bounds.windowState === 'minimized') {
        await session.send('Browser.setWindowBounds', {
          windowId,
          bounds: { windowState: 'normal' },
        });
      }
      await page.bringToFront();
    } finally {
      await session.detach();
    }
  }
  return page.screenshot(options);
}

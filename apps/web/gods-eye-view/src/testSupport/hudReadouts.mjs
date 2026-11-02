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

// src/testSupport/hudReadouts.mjs — the Intel HUD's published readouts by the
// element ids its view renders them in, for tests that drive IntelHUD alone.

const FIELDS = Object.freeze({
  'hud-alt': 'alt',
  'hud-summary': 'summary',
  'hud-mgrs': 'mgrs',
  'hud-latlon': 'latlon',
  'hud-bottom-line': 'bottom',
  'hud-gsd': 'gsd',
  'hud-coll': 'coll',
  'hud-ona': 'ona',
  'hud-mode': 'mode',
  'hud-timestamp': 'timestamp',
});

/**
 * A `publish` to hand IntelHUD and each readout's latest text.
 * @returns {{publish: (view: object) => void, view: () => ?object,
 *   elements: Map<string, {readonly textContent: string}>}}
 */
export function hudReadouts() {
  let view = null;
  const elements = new Map(
    Object.entries(FIELDS).map(([id, field]) => [
      id,
      {
        get textContent() {
          return view?.[field] ?? '';
        },
      },
    ]),
  );
  return { publish: (next) => (view = next), view: () => view, elements };
}

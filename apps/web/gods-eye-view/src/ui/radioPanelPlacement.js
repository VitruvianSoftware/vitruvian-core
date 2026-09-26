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

/** Keep Radio in Context in every theme, reusing the same playback controls. */
export function syncRadioPanelPlacement(doc) {
  if (!doc?.getElementById) return;
  const panel = doc.getElementById('radio-panel');
  const context = doc.getElementById('global-context-panel');
  const dock = doc.getElementById('context-radio-dock');
  const mini = doc.getElementById('context-radio-mini');
  const parent =
    context?.querySelector('.cyber-panel-body') ||
    context?.querySelector('.global-context-panel-inner');
  const header = context?.querySelector('.panel-header');
  if (!panel || !parent || !header || !dock || !mini) return;
  if (panel.parentElement !== parent) parent.append(panel);
  if (dock.parentElement !== header)
    header.insertBefore(dock, header.querySelector('.panel-collapse-btn'));
  if (mini.parentElement !== dock) dock.append(mini);
}

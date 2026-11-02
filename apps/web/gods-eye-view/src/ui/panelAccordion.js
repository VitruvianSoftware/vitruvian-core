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
 * Keep one side panel open on desktop, and on phones put back the collapse
 * this applied, since a sheet shows several panels at once. The owner is the
 * most recently opened panel, then the one holding keyboard focus, then the
 * first. `accordion-collapsed` marks the collapse as presentation only, so
 * saved and shared preferences still report the panel as the user left it.
 * @param {object} options
 * @param {HTMLElement[]} options.panels The side's laid-out panels.
 * @param {boolean} options.enabled Whether the one-panel rule applies.
 * @param {string} [options.preferredPanelId] Most recently opened panel.
 * @param {Document} [options.documentRef] Document supplying keyboard focus.
 * @param {Function} options.onCollapse Present a panel's collapse:
 *   `(panel, {collapsed, auto})`.
 */
export function settleSideAccordion({
  panels,
  enabled,
  preferredPanelId,
  documentRef,
  onCollapse,
}) {
  if (!enabled) {
    for (const panel of panels) {
      if (!panel.classList.contains('accordion-collapsed')) continue;
      onCollapse(panel, { collapsed: false, auto: null });
    }
    return;
  }
  const expanded = panels.filter(
    (panel) => !panel.classList.contains('collapsed'),
  );
  const owner =
    expanded.find((panel) => panel.id === preferredPanelId) ||
    expanded.find((panel) => panel.contains(documentRef?.activeElement)) ||
    expanded[0];
  for (const panel of expanded) {
    if (panel === owner) continue;
    onCollapse(panel, { collapsed: true, auto: 'accordion' });
  }
}

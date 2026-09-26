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
 * Measure unconstrained visible content without feeding the allocated outer
 * height back into the next layout pass.
 * @param {HTMLElement} panel Panel whose natural height is needed.
 * @param {Function} getComputedStyle Style reader for the panel's document.
 * @returns {number} Natural height in CSS pixels.
 */
export function measurePanelNaturalHeight(panel, getComputedStyle) {
  const inner = [...panel.children].find(
    (child) => !child.classList.contains('panel-glow'),
  );
  if (!inner)
    return Math.ceil(
      panel.scrollHeight || panel.getBoundingClientRect().height,
    );

  const innerRect = inner.getBoundingClientRect();
  const panelStyle = getComputedStyle(panel);
  const innerStyle = getComputedStyle(inner);
  const paddingBottom = parseFloat(innerStyle.paddingBottom) || 0;
  let contentBottom = parseFloat(innerStyle.paddingTop) || 0;

  for (const child of inner.children) {
    const childStyle = getComputedStyle(child);
    if (childStyle.display === 'none' || childStyle.visibility === 'hidden')
      continue;
    const childRect = child.getBoundingClientRect();
    const marginBottom = parseFloat(childStyle.marginBottom) || 0;
    const naturalChildHeight = Math.max(
      childRect.height,
      child.scrollHeight || 0,
    );
    const childBottom =
      childRect.top - innerRect.top + naturalChildHeight + marginBottom;
    contentBottom = Math.max(contentBottom, childBottom);
  }

  const wrapperChrome =
    (parseFloat(panelStyle.borderTopWidth) || 0) +
    (parseFloat(panelStyle.borderBottomWidth) || 0) +
    (parseFloat(panelStyle.paddingTop) || 0) +
    (parseFloat(panelStyle.paddingBottom) || 0);
  return Math.ceil(contentBottom + paddingBottom + wrapperChrome);
}

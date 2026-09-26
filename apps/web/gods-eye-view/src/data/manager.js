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

import { LayerLifecycle } from './lifecycle.js';
import { LayerPresentation } from '../app/layerPresentation.js';
export { layerFeedState } from '../ui/layers.js';

/** Compatibility facade for callers that construct a manager with its panel. */
export class DataLayerManager extends LayerLifecycle {
  constructor(viewer, options) {
    super(viewer, options);
    this._presentation = new LayerPresentation(this);
  }
  buildTogglePanel(container) {
    this._presentation.mount(container);
  }
  _refreshTogglePanel() {
    this._presentation.refresh();
  }

  /**
   * Repaint the toggle panel now. For layers whose data arrives outside their
   * manager tick (camera-driven loads such as Transit's proximity polls), so a
   * row shows its count when the data lands instead of at the next interval.
   * One DOM pass; skipped while the document is hidden.
   */
  refreshLayerStats() {
    this._refreshTogglePanel();
  }

  _buildMetaText(layer) {
    return this._presentation.panel._buildMetaText(layer);
  }
  _syncToggleButton(button, layer) {
    return this._presentation.panel._syncToggleButton(button, layer);
  }
  get _layerPanel() {
    return this._presentation._panel;
  }
  get _panelRefreshPendingOnVisible() {
    return this._presentation.pendingVisible;
  }
  set _panelRefreshPendingOnVisible(value) {
    this._presentation.pendingVisible = value;
  }
}

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

export function createTesting({ state: layerState, services, parts, source }) {
  /** Seed a selected-station runtime record while still exercising real select/clear paths. */

  function _setBikeshareSelectionStateForTest({
    viewer,
    key,
    record,
    overlayHost,
  }) {
    layerState._viewer = viewer;
    layerState._stationRenderMap = new Map([[key, record]]);
    layerState._selectedKey = null;
    layerState._selectedEntity = null;
    layerState._overlayHost = overlayHost || layerState.DEFAULT_OVERLAY_HOST;
  }

  /** Exercise the production selection path in focused runtime tests. */

  function _selectBikeshareStationForTest(key) {
    parts.selection._selectStation(key);
  }

  /** Exercise the production clear path and restore the production host seam. */

  function _clearBikeshareSelectionForTest() {
    parts.selection._clearSelection();
    layerState._overlayHost = layerState.DEFAULT_OVERLAY_HOST;
  }
  return {
    _setBikeshareSelectionStateForTest,
    _selectBikeshareStationForTest,
    _clearBikeshareSelectionForTest,
  };
}

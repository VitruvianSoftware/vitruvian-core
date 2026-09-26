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

import { createApplicationBikeshare } from '../app/layers/bikeshare.js';
import { createSourceSlot } from '../sources/sourceSlot.js';
import { createBikeshareSource } from '../layers/bikeshare/source.js';

const sourceSlot = createSourceSlot(
  createBikeshareSource(),
  ['getStations'],
  'Bikeshare source',
);
export const configureBikeshareSource = sourceSlot.configure;
const layer = createApplicationBikeshare({
  source: sourceSlot.source,
});
export const createBikeshareSelectedOverlayEntry =
  layer.createBikeshareSelectedOverlayEntry;
export const _setBikeshareSelectionStateForTest =
  layer._setBikeshareSelectionStateForTest;
export const _selectBikeshareStationForTest =
  layer._selectBikeshareStationForTest;
export const _clearBikeshareSelectionForTest =
  layer._clearBikeshareSelectionForTest;
export {
  BIKESHARE_SELECTED_OVERLAY_SOURCE_ID,
  BIKESHARE_SELECTED_OVERLAY_SOURCE_OPTIONS,
} from '../layers/bikeshare/index.js';
export default layer;

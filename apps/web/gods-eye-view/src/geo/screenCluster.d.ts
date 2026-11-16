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

/** Screen-space clustering of drawn points (`screenCluster.js`). */
import type { Ecef, ScreenXY } from '../render/contract/index';

export interface ScreenClusterPoint {
  id: string;
  position: Ecef;
  screen: ScreenXY;
  /** Its drawn size, CSS pixels. */
  pixelSize: number;
}

/** What a pass leaves for the next. */
export interface ScreenClusterState {
  clusters: Array<{
    position: Ecef;
    width: number;
    height: number;
    minimumWidth: number;
    minimumHeight: number;
  }>;
  /** The eye's height above the ground at that pass. */
  height: number;
}

export function clusterScreenPoints(options: {
  points: ScreenClusterPoint[];
  pixelRange: number;
  minimumClusterSize: number;
  /** The view's height, CSS pixels. */
  viewHeight: number;
  /** The eye's height above the ground, m. */
  eyeHeight: number;
  previous?: ScreenClusterState | null;
  project: (position: Ecef) => ScreenXY | null;
  isOccluded: (position: Ecef) => boolean;
}): {
  clusters: Array<{ position: Ecef; ids: string[] }>;
  single: string[];
  state: ScreenClusterState;
};

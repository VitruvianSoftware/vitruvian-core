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
 * Wind streamlines baked from a wind grid (`streamlines.js`): the paths a
 * `windStreamlines` field draws.
 */

/** A wind grid: row-major from `la1` (north) southward. */
export interface WindGrid {
  u: Float32Array;
  v: Float32Array;
  nx: number;
  ny: number;
  lo1: number;
  la1: number;
  dx: number;
  dy: number;
}

export interface WindPath {
  coordinates: Array<[lon: number, lat: number]>;
  speed: number;
  seed: number;
  phase: number;
}

export const WIND_PATH_LIMIT: number;
export const WIND_NARROW_PATH_LIMIT: number;
export const WIND_PATH_STEPS: number;
export const WIND_DISPLAY_HEIGHT_METERS: number;
export const WIND_CELL_DEGREES: number;

/**
 * Bake streamlines once from a wind grid; with `bounds` (degrees), seeds
 * fall inside it and paths stop at its edges.
 */
export function bakeWindStreamlines(
  grid: WindGrid,
  options?: {
    count?: number;
    steps?: number;
    stepSeconds?: number;
    bounds?: {
      west: number;
      south: number;
      east: number;
      north: number;
    } | null;
  },
): WindPath[];

/** Group baked paths by their middle coordinate. */
export function groupWindPaths(
  paths: WindPath[],
  cellDegrees?: number,
): Array<{ id: number; paths: WindPath[] }>;

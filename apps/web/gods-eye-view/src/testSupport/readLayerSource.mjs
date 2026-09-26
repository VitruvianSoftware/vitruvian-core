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

import { readFileSync, readdirSync } from 'node:fs';
import { dirname, join, basename } from 'node:path';
import { fileURLToPath } from 'node:url';

/** Read actual component owners for structural regression assertions. */
export function readLayerSource(file) {
  const path = file instanceof URL ? fileURLToPath(file) : file;
  if (
    ![
      'flights.js',
      'militaryFlights.js',
      'aisLiveVessels.js',
      'firmsHeatmap.js',
      'satellites.js',
      'rocketLaunches.js',
      'militaryInstallations.js',
      'militaryAwareness.js',
      'traffic.js',
      'bikeshare.js',
      'cctv.js',
    ].includes(basename(path))
  )
    return readFileSync(path, 'utf8');
  const directory = join(
    dirname(path),
    basename(path) === 'flights.js'
      ? '../layers/flights'
      : basename(path) === 'militaryFlights.js'
        ? '../layers/military'
        : basename(path) === 'firmsHeatmap.js'
          ? '../layers/firms'
          : basename(path) === 'satellites.js'
            ? '../layers/satellites'
            : basename(path) === 'rocketLaunches.js'
              ? '../layers/launches'
              : basename(path) === 'militaryInstallations.js'
                ? '../layers/installations'
                : basename(path) === 'militaryAwareness.js'
                  ? '../layers/awareness'
                  : basename(path) === 'traffic.js'
                    ? '../layers/traffic'
                    : basename(path) === 'bikeshare.js'
                      ? '../layers/bikeshare'
                      : basename(path) === 'cctv.js'
                        ? '../layers/cctv'
                        : '../layers/vessels',
  );
  return readdirSync(directory)
    .filter((name) => name.endsWith('.js'))
    .sort()
    .map((name) => readFileSync(join(directory, name), 'utf8'))
    .join('\n');
}

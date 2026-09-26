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

import { formatWindSpeed, WIND_UNITS } from './inspection.js';

/** Reformat a captured sample; changing units never samples the map again. */
export function formatWindReading(reading, units) {
  if (!reading) return null;
  return {
    ...reading,
    units,
    scalarValue:
      reading.scalarKind === 'speed'
        ? formatWindSpeed(reading.speed, units)
        : reading.scalarValue,
    wind: Number.isFinite(reading.speed)
      ? `${formatWindSpeed(reading.speed, units)}${reading.from === 'Calm' ? ' · calm' : ` from ${reading.from}`}`
      : reading.wind,
  };
}

export function windUnitChips(units) {
  return Object.keys(WIND_UNITS).map((value) => ({
    id: `units-${value}`,
    label: value,
    active: units === value,
    params: { units: value },
    title: 'Wind speed units',
  }));
}

/** Portable result block consumed by the WEATHER card. */
export function windReadingResult(reading) {
  return {
    id: 'reading',
    label: `WIND AT ${reading.coordinates.replace(' · ', ' ')}`,
    lines: [
      {
        id: 'wind',
        text: reading.wind,
      },
      {
        id: 'meta',
        text: `${reading.model} · valid ${reading.validTime?.replace(/^\d{4}-/, '')}`,
      },
      ...(reading.scalarValue
        ? [
            {
              id: 'scalar',
              text: `${reading.scalarLabel} · ${reading.scalarValue}`,
            },
          ]
        : []),
      { id: 'explanation', text: reading.explanation },
    ],
    clear: { params: { inspect: false } },
  };
}

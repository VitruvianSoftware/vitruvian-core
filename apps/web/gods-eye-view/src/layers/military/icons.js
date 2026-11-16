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

import { createAircraftIcons } from '../../data/aircraftIconLayer.js';
import { placeAircraftAt } from '../flights/placed.js';
import {
  COCKPIT_CONTACT_SIZE_PX,
  COURSE_MAX_DPS,
  STALE_ALPHA,
  followsClock,
} from './policy.js';

/** The military layer's contacts as one icon set (`createAircraftIcons`). */
export function createIcons({ flightState, services, parts }) {
  return createAircraftIcons({
    state: flightState,
    services,
    parts,
    layerId: 'military',
    displayDelay: flightState._displayDelay,
    followsClock: () => followsClock(flightState),
    staleAlpha: STALE_ALPHA,
    courseMaxDps: COURSE_MAX_DPS,
    cockpitContactSizePx: COCKPIT_CONTACT_SIZE_PX,
    // A host-supplied placement, if any, draws a live contact where it places it.
    placeAt: services.placement
      ? (icao24, wallMs, info, history, out) =>
          placeAircraftAt(
            services.placement,
            icao24,
            wallMs,
            info,
            history,
            out,
          )
      : null,
  });
}

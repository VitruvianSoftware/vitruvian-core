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
 * Transponder emergency status for one aircraft, from the Mode A squawk and
 * the ADS-B emergency/priority field.
 *
 * Emergency squawks are ICAO-standard worldwide: 7500 unlawful interference,
 * 7600 radio failure, 7700 general emergency. readsb (adsb.lol) also reports
 * `emergency`, "a superset of the 7x00 squawks": none, general, lifeguard,
 * minfuel, nordo, unlawful, downed, reserved. OpenSky state vectors carry the
 * squawk only.
 *
 * The status is what the transponder broadcast in THIS poll, never a finding:
 * crews pass through 7x00 codes while dialling. Highlighting follows the latest
 * broadcast, which does not confirm an incident or its resolution.
 */

import { msg } from '../i18n/marker.js';

/** @constant {string} Tint for aircraft broadcasting an emergency (not a priority). */
export const EMERGENCY_TINT_CSS = '#FF4444';

const SQUAWK_KINDS = { 7500: 'unlawful', 7600: 'nordo', 7700: 'general' };

const KINDS = {
  general: { label: msg('General emergency'), severity: 'emergency' },
  unlawful: { label: msg('Unlawful interference'), severity: 'emergency' },
  nordo: { label: msg('Radio failure'), severity: 'emergency' },
  downed: { label: msg('Downed aircraft'), severity: 'emergency' },
  minfuel: { label: msg('Minimum fuel'), severity: 'priority' },
  lifeguard: {
    label: msg('Lifeguard (medical priority)'),
    severity: 'priority',
  },
};

/**
 * A Mode A code as its four octal digits, else null.
 * @param {unknown} value
 * @returns {string|null}
 */
export function normalizeSquawk(value) {
  const code = String(value ?? '').trim();
  return /^[0-7]{4}$/.test(code) ? code : null;
}

/**
 * Emergency status from one observation. Higher severity wins; an ADS-B
 * emergency wins a tie. A
 * 7x00 squawk counts even when the ADS-B field says `none`.
 * @param {{squawk?: unknown, emergency?: unknown}} [observation]
 * @returns {{kind: string, label: string, severity: 'emergency'|'priority',
 *   squawk: string|null, source: 'ads-b'|'squawk'}|null} `source` is
 *   'squawk' when the Mode A code itself names the status (so it can be
 *   quoted), else 'ads-b'.
 */
export function aircraftEmergency({ squawk, emergency } = {}) {
  const code = normalizeSquawk(squawk);
  const reported = String(emergency ?? '')
    .trim()
    .toLowerCase();
  const fromAdsb = Object.hasOwn(KINDS, reported);
  const squawkKind = SQUAWK_KINDS[code] ?? null;
  const kind =
    fromAdsb && (KINDS[reported].severity === 'emergency' || !squawkKind)
      ? reported
      : squawkKind;
  if (!kind) return null;
  return {
    kind,
    ...KINDS[kind],
    squawk: code,
    source: SQUAWK_KINDS[code] === kind ? 'squawk' : 'ads-b',
  };
}

/**
 * How a summary may phrase the status without flattening it into an incident:
 * quote the code when the Mode A squawk itself names the status, otherwise
 * attribute it to the ADS-B emergency field.
 * @param {{kind?: string, squawk?: string|null, source?: string}|null|undefined} status
 * @returns {string|null} e.g. 'broadcasting squawk 7700 (general emergency)'
 *   or 'ADS-B reports general emergency'; null when there is no status.
 */
export function emergencyBroadcastPhrase(status) {
  if (!status || !Object.hasOwn(KINDS, status.kind)) return null;
  const label = KINDS[status.kind].label.toLowerCase();
  return status.source === 'squawk' && status.squawk
    ? `broadcasting squawk ${status.squawk} (${label})`
    : `ADS-B reports ${label}`;
}

/**
 * True when the aircraft is broadcasting an emergency (not a priority status).
 * @param {{severity?: string}|null|undefined} status
 * @returns {boolean}
 */
export function isEmergency(status) {
  return status?.severity === 'emergency';
}

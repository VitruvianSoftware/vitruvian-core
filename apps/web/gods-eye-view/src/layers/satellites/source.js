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

const GROUPS = new Set([
  'stations',
  'visual',
  'gps-ops',
  'glo-ops',
  'galileo',
  'geo',
  'starlink',
  // Imaging coverage beyond the UCS May 2023 snapshot, and science probes.
  'resource',
  'weather',
  'planet',
  'sar',
  'science',
]);

/** The UCS pack, loaded on first use (see src/data/ucsSatellites.js). */
async function loadBundledUcs() {
  const { loadUcsSatellites } = await import('../../data/ucsSatellites.js');
  return loadUcsSatellites();
}

/** The imaging-sensor pack, loaded on first use (see src/data/imagingSensors.js). */
async function loadBundledSensors() {
  const { loadImagingSensors } = await import('../../data/imagingSensors.js');
  return loadImagingSensors();
}

/** Read catalog text from the existing group endpoint using a supplied transport. */
export function createSatelliteSource({
  fetchImpl = (...args) => globalThis.fetch(...args),
  loadUcs = loadBundledUcs,
  loadSensors = loadBundledSensors,
} = {}) {
  return {
    async readGroup(group, { signal } = {}) {
      if (!GROUPS.has(group)) throw new TypeError('Unknown satellite group');
      signal?.throwIfAborted();
      const response = await fetchImpl(`/api/celestrak/${group}`, { signal });
      const text = response.ok ? await response.text() : '';
      signal?.throwIfAborted();
      // The proxy serves its last copy, marked STALE-ERROR, when CelesTrak
      // is down.
      const stale = response.headers?.get?.('x-tle-cache') === 'STALE-ERROR';
      return { ok: response.ok, status: response.status, text, stale };
    },

    /**
     * CelesTrak SATCAT records (CSV) for one group: object type, operational
     * status and owner, through the proxy's day-long cache.
     */
    async readSatcat(group, { signal } = {}) {
      if (!GROUPS.has(group)) throw new TypeError('Unknown satellite group');
      signal?.throwIfAborted();
      const response = await fetchImpl(`/api/celestrak-satcat/${group}`, {
        signal,
      });
      const text = response.ok ? await response.text() : '';
      signal?.throwIfAborted();
      // The proxy serves its last copy, marked STALE-ERROR, when CelesTrak
      // is down.
      const stale = response.headers?.get?.('x-satcat-cache') === 'STALE-ERROR';
      return { ok: response.ok, status: response.status, text, stale };
    },

    /** The UCS Satellite Database pack, keyed by NORAD number. */
    readUcs() {
      return loadUcs();
    },

    /** The imaging-sensor pack, indexed by NORAD number and name pattern. */
    readSensors() {
      return loadSensors();
    },
  };
}

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

import { HEALTH_SYNC_INTERVAL_MS, HEALTH_ENDPOINT } from './policy.js';

export function createHealth({ state: layerState, services, parts, source }) {
  /**
   * Fetches per-camera health status from the backend and updates _healthById.
   * Rate-limited to HEALTH_SYNC_INTERVAL_MS unless forced.
   * @param {boolean} [force=false] - Bypass the interval check.
   */

  async function syncHealthState(force = false) {
    const now = Date.now();
    if (!force && now - layerState._lastHealthSyncAt < HEALTH_SYNC_INTERVAL_MS)
      return;
    layerState._lastHealthSyncAt = now;

    try {
      const signal = layerState._sourceAbort?.signal;
      const data = await source.getHealth({ signal });
      signal?.throwIfAborted();
      const rows = Array.isArray(data?.cameras) ? data.cameras : [];
      const next = new Map();
      for (const row of rows) {
        const id = String(row?.id || '').trim();
        if (!id) continue;
        next.set(id, {
          status: String(row.status || '').toLowerCase() || 'unknown',
          sourceKind: String(
            row.sourceKind || row.feedType || '',
          ).toLowerCase(),
          label: String(row.label || row.provider || ''),
          message: String(row.message || ''),
          updatedAt: parts.model.safeNumber(row.updatedAt, now),
        });
      }
      layerState._healthById = next;
    } catch {
      // keep previous health map
    }
  }
  return { syncHealthState };
}

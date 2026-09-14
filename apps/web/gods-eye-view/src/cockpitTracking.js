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

/*
 * Cockpit aircraft metadata itself is resolved by `resolveTrackedAircraftInfo`
 * in `cockpitMath.js` — the landed owner of that rule. It keeps layer
 * precedence as the fallback when no normalized `gevTrackedId` is available,
 * so tracking paths that never stamp one keep working; `readAircraftInfo` is
 * pinned to it by `cockpitMarkup.test.mjs`. This module owns only the
 * multi-step ENTRY TRANSACTION (adopt → enter → roll back).
 */

/** Force the prior aircraft layer to reacquire Cesium and durable tracking ownership. */
export function restoreAircraftTrackingOwner(layer, id, { origin = 'programmatic' } = {}) {
  if (!layer?.trackById || !id) return false;
  layer.stopTracking?.({ origin });
  return Boolean(layer.trackById(id, { origin }));
}

/** Normalize Cockpit aircraft metadata into a stable tracking target. */
export function aircraftTrackingTarget(info) {
  if (!info?.layerId || !(info.icao24 || info.id)) return null;
  return {
    layerId: info.layerId,
    id: String(info.icao24 || info.id),
  };
}

/** Enter Cockpit and restore the pre-transaction tracker after every failure form. */
export function enterCockpitWithTracking({
  cockpitView,
  selectedLayer = null,
  selectedTarget = null,
  currentLayer = null,
  rollbackLayer = null,
  rollbackTarget = undefined,
  selectionOrigin = 'programmatic',
}) {
  const currentTarget = aircraftTrackingTarget(cockpitView?.readAircraftInfo?.());
  const restoreTarget = rollbackTarget === undefined ? currentTarget : rollbackTarget;
  const key = (target) => target?.layerId && target?.id
    ? `${target.layerId}:${target.id}`
    : null;
  let activeLayer = currentLayer;
  let activeTarget = currentTarget;
  let entryError = null;
  let entered = false;
  let entryThrew = false;

  try {
    const selectingTarget = Boolean(selectedLayer && selectedTarget?.id);
    if (selectingTarget) {
      activeLayer = selectedLayer;
      activeTarget = selectedTarget;
      if (!selectedLayer.trackById?.(selectedTarget.id, { origin: selectionOrigin })) {
        entryError = new Error('Selected aircraft could not be tracked for Cockpit entry');
      }
    }
    if (!entryError) entered = Boolean(cockpitView.enter());
  } catch (error) {
    entryThrew = true;
    entryError = error instanceof Error ? error : new Error(String(error));
  }

  if (!entered && key(activeTarget) !== key(restoreTarget)) {
    try {
      // Undo the explicit attempted selection through the same persistence
      // authority, then republish the prior target with that origin. A
      // programmatic rollback would fix the camera while leaving the failed
      // target durable in local/share state.
      activeLayer?.stopTracking?.({ origin: selectionOrigin });
      if (restoreTarget && !restoreAircraftTrackingOwner(
        rollbackLayer,
        restoreTarget.id,
        { origin: selectionOrigin },
      )) {
        entryError ||= new Error('Prior aircraft tracking could not be restored');
      }
    } catch (error) {
      entryError ||= error instanceof Error ? error : new Error(String(error));
    }
  }
  if (entryThrew) {
    try {
      cockpitView.exit?.({ restoreTracking: false });
    } catch {
      // Tracker rollback above remains authoritative if partial Cockpit cleanup fails.
    }
  }

  return {
    entered,
    error: entered ? null : entryError?.message || 'Cockpit entry was unavailable',
  };
}

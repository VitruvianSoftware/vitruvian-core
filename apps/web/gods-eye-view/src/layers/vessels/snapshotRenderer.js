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

import { KNOT_MPS } from '../../data/units.js';

const finiteOrNaN = (value) =>
  typeof value === 'number' && Number.isFinite(value) ? value : NaN;

/**
 * A vessel record's fix as a host-supplied placement takes it: its own time
 * (when it was received, if the row gives none), position, speed in m/s
 * (rows give knots), course and heading.
 */
function placementFix(record) {
  const epoch = record.lastPositionEpoch;
  return {
    timeMs: Number.isFinite(epoch) ? epoch * 1000 : record.receivedAtMs,
    lat: record.lat,
    lon: record.lon,
    altitudeM: NaN,
    speedMps: Number.isFinite(record.speed) ? record.speed * KNOT_MPS : NaN,
    courseDeg: finiteOrNaN(record.course),
    headingDeg: finiteOrNaN(record.heading),
  };
}

/**
 * Connect portable vessel reconciliation to scene and selection operations.
 * `placement`, a host-supplied placement, is told each live fix.
 */
export function createVesselSnapshotRenderer({
  state,
  placement = null,
  records,
  rendering,
  tracking,
  selection,
  cards,
  followsClock = () => false,
}) {
  /**
   * `replace`: the rows are the world at another time (see VesselRecords).
   * `handover`: the first live rows after the clock came back to live (see
   * VesselRecords); they are live fixes.
   */
  function reconcileVessels(
    viewer,
    rows,
    { complete = true, replace = false, handover = false } = {},
  ) {
    rendering.ensureCollections(viewer);
    const occluder = rendering.makeOccluder();
    const follow = followsClock();
    // Live fixes only: following the clock, the layer places every vessel.
    const observe =
      placement && !follow && !replace
        ? (record) => {
            if (record.id) placement.observe(record.id, placementFix(record));
          }
        : () => {};
    records.reconcile(
      rows,
      {
        complete,
        selectedRecord: state.selectedRecord,
        cap: rendering.renderRowLimit(),
        ...(replace && { replace }),
        ...(handover && { handover }),
        ...(follow && { follow }),
      },
      {
        add(record) {
          observe(record);
          rendering.prepareRecordVisual(record);
          rendering.addRecordPrimitives(record, occluder);
        },
        updated(record) {
          observe(record);
          const selected = record === state.selectedRecord;
          rendering.prepareRecordVisual(record);
          rendering.syncRecordIcon(record);
          if (record.id === state.trailId)
            tracking.appendSelectedVesselTrailFix(record);
          if (selected) {
            cards.updateSelectedVesselHud(record);
            selection.registerSelectedContext(record);
          }
        },
        remove(record, evicted) {
          if (evicted) selection.clearVesselInspection({ evicted: true });
          rendering.removeRecordPrimitives(record);
        },
        removed(id) {
          placement?.forget(id);
          if (state.trailId === id) tracking.clearSelectedVesselTrail();
        },
        staleSelected(record) {
          cards.updateSelectedVesselHud(record);
        },
      },
    );
    // The selected vessel at the new time: its trail is drawn to it.
    if (replace && state.selectedRecord && state.trailId)
      tracking.retimeSelectedVesselTrail(state.selectedRecord);
    state.lastVisibilityUpdate = 0;
    rendering.updateVisibility(true);
  }
  return { reconcileVessels };
}

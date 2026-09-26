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

/** Connect portable vessel reconciliation to scene and selection operations. */
export function createVesselSnapshotRenderer({
  state,
  records,
  rendering,
  tracking,
  selection,
  cards,
}) {
  function reconcileVessels(viewer, rows, { complete = true } = {}) {
    rendering.ensureCollections(viewer);
    const occluder = rendering.makeOccluder();
    records.reconcile(
      rows,
      {
        complete,
        selectedRecord: state.selectedRecord,
        cap: rendering.renderRowLimit(),
      },
      {
        add(record) {
          rendering.prepareRecordVisual(record);
          rendering.addRecordPrimitives(record, occluder);
        },
        beforeUpdate(record) {
          return rendering.shipIcon(record, record === state.selectedRecord);
        },
        updated(record, prevIcon) {
          const selected = record === state.selectedRecord;
          const visual = rendering.prepareRecordVisual(record);
          if (visual.billboard) {
            visual.billboard.position = visual.position;
            visual.billboard.scale =
              rendering.shipScale(record) * (selected ? 1.2 : 1);
            const nextIcon = rendering.shipIcon(record, selected);
            if (nextIcon !== prevIcon) visual.billboard.image = nextIcon;
          }
          if (record.mmsi === state.trailMmsi)
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
        removed(mmsi) {
          if (state.trailMmsi === mmsi) tracking.clearSelectedVesselTrail();
        },
        staleSelected(record) {
          cards.updateSelectedVesselHud(record);
        },
      },
    );
    state.lastVisibilityUpdate = 0;
    rendering.updateVisibility(true);
  }
  return { reconcileVessels };
}

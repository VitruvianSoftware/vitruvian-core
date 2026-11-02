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

export function _syncContextModeButtons() {
  if (this.destroyed) return;
  this._presentContext();
  this.cockpitView?.syncEntry();
  // Every _contextMode mutation funnels through here; the sync no-ops until
  // the transaction settles, so this is the activation/deactivation edge.
  this.actions.syncDetection();
  this.actions.scheduleLayout();
}

/** Publish the mode switch and the nearby sites search to the view. */
export function _presentContext() {
  if (this.destroyed) return;
  const flightsActive = this._contextMode === 'flights';
  const missionsActive = this._contextMode === 'space-missions';
  // Both Context choices stay in the ordinary Tab sequence and are never
  // native-disabled. Arrow keys still provide tablist navigation, but must
  // not be the only way to reach Space Missions from the keyboard. Semantic
  // busy state keeps them perceivable while synchronous click guards prevent
  // a second transition.
  this.publish({
    mode: this._contextMode || 'none',
    enabled: flightsActive || missionsActive,
    flightsActive,
    missionsActive,
    busy: Boolean(this._contextModeChanging),
    installationsBusy: this._installationsSearchBusy,
  });
}

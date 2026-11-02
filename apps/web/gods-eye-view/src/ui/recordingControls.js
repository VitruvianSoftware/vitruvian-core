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
 * Own recording chrome, safe frames and the pre-recording HUD snapshot. The
 * safe frame a recording composes in goes to `publishSafeFrame` ('16:9',
 * '9:16', or null while none records); the scene chrome renders it.
 */
export class RecordingControls {
  constructor({
    syncShareState,
    syncHudControls,
    publishSafeFrame = () => {},
  }) {
    this._syncShareState = syncShareState;
    this._publishSafeFrame = publishSafeFrame;
    // Shows the HUD's visibility and layout on the Display controls.
    this._syncHudControls = syncHudControls;
    this.destroyed = false;
    this._recordingMode = false;
    this._recordingConfig = {
      hidePanels: true,
      hudMode: 'minimal',
      safeFrame: '16:9',
    };
    this._preRecordingHudState = null;
    this.hud = null;
  }
  _initRecordingOverlay() {
    if (!this.destroyed) this._publishSafeFrame(null);
  }

  setRecordingMode(enabled, options = {}) {
    if (this.destroyed) return;
    const {
      hidePanels = true,
      hudMode = 'minimal',
      safeFrame = '16:9',
    } = options;
    this._recordingMode = !!enabled;
    this._recordingConfig = { hidePanels, hudMode, safeFrame };

    document.body.classList.toggle(
      'recording-mode',
      this._recordingMode && hidePanels,
    );

    this._publishSafeFrame(this._recordingMode ? (safeFrame ?? '16:9') : null);

    if (this._recordingMode) {
      // Snapshot the user's HUD state once per recording session so exit can
      // restore it (re-entrant calls must not capture mid-recording state).
      if (!this._preRecordingHudState) {
        this._preRecordingHudState = {
          mode: this.hud.getMode(),
          variant: this.hud.getVariant(),
        };
      }
      if (hudMode === 'off') {
        this.hud.setMode('off');
      } else if (hudMode === 'full' || hudMode === 'minimal') {
        this.hud.setMode('on');
        this.hud.setVariant(hudMode === 'minimal' ? 'minimal' : 'tactical');
      } else {
        this.hud.setMode('auto');
      }
    } else {
      const saved = this._preRecordingHudState;
      this._preRecordingHudState = null;
      if (saved) {
        this.hud.setVariant(saved.variant);
      }
      this.hud.setMode(saved ? saved.mode : 'auto');
    }
    this._syncHudControls();
    this._syncShareState();
  }
  destroy() {
    if (this.destroyed) return;
    // Restore an active session while its supplied HUD is still alive.
    if (this._recordingMode) this.setRecordingMode(false);
    this.destroyed = true;
  }
}

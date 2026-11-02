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

/** Resolve the fixed DOM nodes used to assemble the application controls. */
export function readShellElements(document = globalThis.document) {
  return {
    _rightPanelStack: document.getElementById('right-context-rail'),
    _sliderPanel: document.getElementById('param-slider-panel'),
    _ppToggles: document.getElementById('pp-toggles'),
    _bloomBtn: document.getElementById('bloom-toggle'),
    _bloomSlider: document.getElementById('bloom-intensity-slider'),
    _hudBtn: document.getElementById('hud-toggle'),
    _cleanViewBtn: document.getElementById('clean-view-toggle'),
    _dataPanel: document.getElementById('data-panel'),
    _scenePanel: document.getElementById('scene-panel'),
    _cctvPanel: document.getElementById('cctv-panel'),
    _streetLevelPanel: document.getElementById('street-level-panel'),
    _radioPanel: document.getElementById('radio-panel'),
    _cockpitUtilityControls: document.getElementById(
      'cockpit-utility-controls',
    ),
    _cockpitDisplayToggleBtn: document.getElementById(
      'cockpit-display-toggle-btn',
    ),
    _cockpitDisplayPanel: document.getElementById('cockpit-display-panel'),
    _cockpitRadioToggleBtn: document.getElementById('cockpit-radio-toggle-btn'),
    _cockpitRadioEnableBtn: document.getElementById('cockpit-radio-enable-btn'),
    _radioLayerState: document.getElementById('radio-layer-state'),
    _radioEnableBtn: document.getElementById('radio-enable-btn'),
    _radioStationName: document.getElementById('radio-station-name'),
    _radioStationMeta: document.getElementById('radio-station-meta'),
    _radioStationTags: document.getElementById('radio-station-tags'),
    _radioTunerSlider: document.getElementById('radio-tuner-slider'),
    _radioVolume: document.getElementById('radio-volume'),
    _radioVolumeValue: document.getElementById('radio-volume-value'),
    _radioPlaybackState: document.getElementById('radio-playback-state'),
    _radioStationHomepage: document.getElementById('radio-station-homepage'),
    _globalContextFlightsBtn: document.getElementById(
      'global-context-flights-btn',
    ),
    _globalContextMissionsBtn: document.getElementById(
      'global-context-missions-btn',
    ),
    _installationsSearchBtn: document.getElementById(
      'installations-search-btn',
    ),
    _leftPanelStack: document.getElementById('left-panel-stack'),
    _cctvEnableBtn: document.getElementById('cctv-enable-btn'),
    _cctvNearestBtn: document.getElementById('cctv-nearest-btn'),
    _cctvPrevBtn: document.getElementById('cctv-prev-btn'),
    _cctvNextBtn: document.getElementById('cctv-next-btn'),
    _cctvSelect: document.getElementById('cctv-camera-select'),
    _cctvFocusBtn: document.getElementById('cctv-focus-btn'),
    _cctvCoverageBtn: document.getElementById('cctv-coverage-btn'),
    _cctvAutoHopBtn: document.getElementById('cctv-auto-hop-btn'),
    _cctvProjectionBtn: document.getElementById('cctv-projection-btn'),
    _cctvQualityChip: document.getElementById('cctv-quality-chip'),
    _cctvAdjustBtn: document.getElementById('cctv-adjust-btn'),
    _cctvCalReadout: document.getElementById('cctv-cal-readout'),
    _cctvCalibSaveBtn: document.getElementById('cctv-calib-save-btn'),
    _cctvCalibResetBtn: document.getElementById('cctv-calib-reset-btn'),
    _cctvFrame: document.getElementById('cctv-frame'),
    _cctvFrameWrap: document.getElementById('cctv-frame-wrap'),
    _cctvVideo: document.getElementById('cctv-video'),
    _cctvSourceBadge: document.getElementById('cctv-source-badge'),
    _cctvMeta: document.getElementById('cctv-meta'),
    _cctvSummary: document.getElementById('cctv-summary'),
    _locationSearch: document.getElementById('location-search'),
    _detectionBtn: document.getElementById('detection-toggle'),
    _models3dBtn: document.getElementById('models3d-toggle'),
  };
}

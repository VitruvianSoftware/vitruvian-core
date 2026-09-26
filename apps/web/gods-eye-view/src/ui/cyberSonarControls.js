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

import {
  isCyberSonarEnabled,
  isCyberSonarActive,
  isCyberContactSonarActive,
  readCyberSonarSettings,
} from '../cyberSonar.js';

const SETTING_FIELDS = Object.freeze({
  rings: ['rings', 3, 12],
  rangePct: ['range', 60, 120],
  intensityPct: ['intensity', 0, 100],
  opacityPct: ['opacity', 35, 100],
  sectorDeg: ['sector', 8, 60],
});

/** Read configuration separately from whether map effects can currently run. */
export function getCyberSonarControlState(doc = globalThis.document) {
  const root = doc?.documentElement;
  const settings = readCyberSonarSettings(root);
  const options = {
    root,
    body: doc?.body,
    hud: doc?.getElementById?.('intel-hud') ?? null,
  };
  return {
    enabled: isCyberSonarEnabled(root),
    rings: settings.rings,
    rangePct: settings.range,
    intensityPct: settings.intensity,
    opacityPct: settings.opacity,
    sectorDeg: settings.sector,
    cyberSelected: root?.dataset?.uiTheme === 'cyber',
    mapSweepActive: isCyberSonarActive(options),
    contactSweepActive:
      root?.dataset?.cyberSonarGpu === 'supported' &&
      isCyberContactSonarActive(options),
    contactRenderer: root?.dataset?.cyberSonarGpu ?? 'not-initialized',
  };
}

/** Validate every field before mutating through the same owner as the sliders. */
export function setCyberSonarControls(
  owner,
  request,
  doc = globalThis.document,
) {
  const fail = (error) => ({
    ok: false,
    error,
    sonar: getCyberSonarControlState(doc),
  });
  if (!request || typeof request !== 'object' || Array.isArray(request)) {
    return fail('Provide Cyber sonar settings as an object.');
  }
  const fields = Object.keys(request);
  if (!fields.length) return fail('Provide at least one Cyber sonar setting.');
  for (const field of fields) {
    const value = request[field];
    if (field === 'enabled') {
      if (typeof value !== 'boolean') return fail('enabled must be a boolean.');
      continue;
    }
    if (!Object.hasOwn(SETTING_FIELDS, field)) {
      return fail('Unknown Cyber sonar setting.');
    }
    const [, min, max] = SETTING_FIELDS[field];
    if (!Number.isInteger(value) || value < min || value > max) {
      return fail(`${field} must be an integer from ${min} to ${max}.`);
    }
  }
  if (
    owner.hud?.getVariant?.() !== 'cyber' ||
    doc?.documentElement?.dataset?.uiTheme !== 'cyber'
  ) {
    return fail('Cyber sonar controls require the Cyber HUD layout.');
  }
  for (const [field, [setting]] of Object.entries(SETTING_FIELDS)) {
    if (Object.hasOwn(request, field)) {
      owner._setCyberSonarSetting(setting, request[field]);
    }
  }
  if (Object.hasOwn(request, 'enabled')) {
    owner._setCyberSonarEnabled(request.enabled);
  }
  return { ok: true, sonar: getCyberSonarControlState(doc) };
}

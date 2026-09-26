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

import * as Cesium from 'cesium';
import { destinationPointDeg } from './model.js';
import { DIRECTION_CONE_M, DIRECTION_CONE_HALF_ANGLE_DEG } from './policy.js';

// Camera artwork and visual treatment contributed by Manjunath (@manjunath22466).
// Module-relative assets also resolve when the layer is consumed by another app.
export const MARKER_IMAGE = new URL(
  './assets/alpr-marker-normal.png',
  import.meta.url,
).href;
export const SELECTED_IMAGE = new URL(
  './assets/alpr-marker-selected.png',
  import.meta.url,
).href;
export const BRACKETS_IMAGE = new URL(
  './assets/alpr-marker-selected-brackets.png',
  import.meta.url,
).href;

/** Compact display label; selection identity always uses the full record id. */
export function alprDisplayId(record) {
  if (!Number.isSafeInteger(record.osmId)) return 'ALPR CAMERA';
  return `ALPR-${String(record.osmId).slice(-4).padStart(4, '0')}`;
}

/** Show only supplied metadata, with the actual source named for custom adapters. */
export function alprLabelDetails(record, source) {
  const sourceName =
    source.attribution?.name || source.label || 'Camera source';
  const details = [
    sourceName === 'OpenStreetMap' ? 'OSM MAPPED' : `Source: ${sourceName}`,
  ];
  if (Number.isFinite(record.directionDeg))
    details.push(`DIRECTION ${Math.round(record.directionDeg)}°`);
  const equipment = [
    ...new Set(
      [record.manufacturer, record.operator, record.cameraType]
        .map((value) =>
          String(value || '')
            .trim()
            .toUpperCase(),
        )
        .filter(Boolean),
    ),
  ];
  if (equipment.length) details.push(equipment.join(' · '));
  if (sourceName === 'OpenStreetMap') details.push('PUBLIC MAP DATA');
  return details;
}

/** Illustrative bearing wedge, not measured field of view or operating range. */
export function directionWedgePositions(record, heightM = 0) {
  if (!Number.isFinite(record.directionDeg)) return null;
  const left = destinationPointDeg(
    record.latitude,
    record.longitude,
    record.directionDeg - DIRECTION_CONE_HALF_ANGLE_DEG,
    DIRECTION_CONE_M,
  );
  const right = destinationPointDeg(
    record.latitude,
    record.longitude,
    record.directionDeg + DIRECTION_CONE_HALF_ANGLE_DEG,
    DIRECTION_CONE_M,
  );
  return [
    Cesium.Cartesian3.fromDegrees(record.longitude, record.latitude, heightM),
    Cesium.Cartesian3.fromDegrees(left.longitude, left.latitude, heightM),
    Cesium.Cartesian3.fromDegrees(right.longitude, right.latitude, heightM),
  ];
}

/** Paint the original cyan/coral gradient with a crisp V-shaped boundary. */
export function paintDirectionWedge(ctx, origin, left, right, selected) {
  const rgb = selected ? '255, 100, 116' : '82, 212, 255';
  const gradient = ctx.createLinearGradient(
    origin.x,
    origin.y,
    (left.x + right.x) / 2,
    (left.y + right.y) / 2,
  );
  const alpha = selected ? [0.8, 0.48, 0.22, 0.06] : [0.34, 0.2, 0.09, 0.025];
  [0, 0.36, 0.72, 1].forEach((stop, i) =>
    gradient.addColorStop(stop, `rgba(${rgb}, ${alpha[i]})`),
  );
  ctx.beginPath();
  ctx.moveTo(origin.x, origin.y);
  ctx.lineTo(left.x, left.y);
  ctx.lineTo(right.x, right.y);
  ctx.closePath();
  ctx.fillStyle = gradient;
  ctx.fill();
  ctx.beginPath();
  ctx.moveTo(left.x, left.y);
  ctx.lineTo(origin.x, origin.y);
  ctx.lineTo(right.x, right.y);
  ctx.strokeStyle = `rgba(${rgb}, ${selected ? 0.98 : 0.76})`;
  ctx.lineWidth = selected ? 2.5 : 1.5;
  ctx.lineJoin = 'round';
  ctx.stroke();
}

/** Reject transient tile/terrain samples outside plausible mapped ground heights. */
export function validAlprGroundHeight(height) {
  return Number.isFinite(height) && height >= -500 && height <= 10000;
}

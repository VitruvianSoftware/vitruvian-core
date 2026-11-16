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
 * Icon motion segments packed for the GPU (`iconSegment.js`): one row per
 * icon, read by `ICON_SEGMENT_GLSL` as `iconPosition` draws it.
 */
import type { Ecef } from '../render/contract/index';

/** Floats per packed row. */
export const SEGMENT_STRIDE: number;
export const SEGMENT_HOLD: number;
export const SEGMENT_LERP: number;
export const SEGMENT_ARC: number;
/** GLSL that evaluates a packed row. */
export const ICON_SEGMENT_GLSL: string;

/** Stay at `position` facing `courseDeg`. */
export function writeHoldSegment(
  out: Float32Array,
  row: number,
  position: Ecef,
  courseDeg: number,
): void;
export function writeLerpSegment(
  out: Float32Array,
  row: number,
  segment: {
    from: Ecef;
    to: Ecef;
    t0: number;
    t1: number;
    course0Deg: number;
    courseSlopeDeg: number;
  },
): void;
export function writeArcSegment(
  out: Float32Array,
  row: number,
  segment: {
    fix: Ecef;
    t0: number;
    minDt: number;
    maxDt: number;
    speedMps: number;
    trackDeg: number;
    turnRateDps: number;
    climbMps?: number;
  },
): void;
/**
 * Glide row `row`'s drawn course from `fromCourseDeg` onto its segment's,
 * at most `rateDps` from `t0` (seconds, as its times were packed).
 */
export function writeCourseGlide(
  out: Float32Array,
  row: number,
  fromCourseDeg: number,
  t0: number,
  rateDps: number,
  offsetDeg?: number,
): void;
/** Move a row's stored times by `deltaSec`. */
export function shiftSegmentTimes(
  out: Float32Array,
  row: number,
  deltaSec: number,
): void;
/** The displayed course at `tau`, degrees clockwise from north. */
export function segmentCourse(
  seg: Float32Array,
  row: number,
  tau: number,
): number;
/** The course the row glides toward at `tau`. */
export function segmentTargetCourse(
  seg: Float32Array,
  row: number,
  tau: number,
): number;
/** Where the row is at `tau`, ECEF, into `result`. */
export function segmentPosition(
  seg: Float32Array,
  row: number,
  tau: number,
  result?: Ecef,
): Ecef;

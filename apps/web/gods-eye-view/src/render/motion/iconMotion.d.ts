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
 * Where an icon is drawn along its motion segment, and with what course
 * (`iconMotion.js`): where the renderer draws a moving icon.
 */
import type {
  CourseGlide,
  Ecef,
  MotionSegment,
  Position,
} from '../contract/index';

/** Below this turn rate, rad/s, an arc is drawn as a straight line. */
export const STRAIGHT_BELOW_RAD_PER_S: number;
/** The shortest a lerp runs, ms: one with no length steps. */
export const LERP_STEP_MS: number;
/** An angle in degrees, wrapped into (-180, 180]. */
export function norm180(deg: number): number;
/** An angle in degrees, wrapped into [0, 360). */
export function norm360(deg: number): number;
/** Where `segment` puts an icon at `t` (epoch ms), from its own `pos`. */
export function motionPosition(
  segment: MotionSegment | undefined,
  pos: Position,
  t: number,
): Ecef;
/** How far, degrees in (-180, 180], a glide starts from its segment's course. */
export function glideOffset(
  segment: MotionSegment | undefined,
  course: number | undefined,
  glide: CourseGlide,
): number;
/** The course drawn at `t`, degrees clockwise from north in [0, 360). */
export function motionCourse(
  segment: MotionSegment | undefined,
  course: number | undefined,
  t: number,
  glide?: CourseGlide,
): number;
/** Where an icon item is drawn at `t` (epoch ms on its set's motion clock). */
export function iconPosition(
  item: { pos: Position; motion?: MotionSegment },
  t: number,
): Ecef;
/** The course an icon item is drawn with at `t`. */
export function iconCourse(
  item: { course?: number; motion?: MotionSegment; courseGlide?: CourseGlide },
  t: number,
): number;
/** Until when, epoch ms, an item's drawn position or course may change. */
export function motionEndsAt(item: {
  motion?: MotionSegment;
  courseGlide?: CourseGlide;
}): number;

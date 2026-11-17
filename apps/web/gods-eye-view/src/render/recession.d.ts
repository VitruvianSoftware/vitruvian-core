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
 * How a set that recedes (`SetSpec.recede`) shrinks and fades its items
 * toward the globe's limb (`recession.js`), so the renderer draws exactly
 * those factors.
 */
import type { RecedeSpec } from './contract/index';

/** A set's `recede` with every parameter filled in. */
export type RecedeParams = Required<RecedeSpec>;

/** What a frame's items recede by, from the eye's height. */
export interface RecedeFrame {
  /** False: nothing recedes this frame (the eye is over the blend band). */
  active: boolean;
  /** The distance from the eye to the limb, metres (1 while not active). */
  limbM: number;
  /** 1 under the blend band, easing to 0 across it. */
  strength: number;
}

export interface RecedeFactors {
  scale: number;
  /** The haze: what the item's alpha recedes by before focus and the floor. */
  alpha: number;
  /** The item's distance as a share of the limb's; null while not active. */
  limbRatio: number | null;
}

/** What a set that recedes takes for what its `recede` leaves out. */
export const RECEDE_DEFAULTS: Readonly<RecedeParams>;

/**
 * A set's `recede` as the parameters it draws with (each clamped to what
 * draws, the rest from `base`); null when the set does not recede.
 */
export function recedeParams(
  spec: RecedeSpec | null | undefined,
  base?: RecedeParams,
): RecedeParams | null;

/** The distance from an eye this high to the limb; NaN at or under the surface. */
export function limbDistanceM(heightM: number, earthRadiusM?: number): number;

export function recedeFrame(
  cameraHeightM: number,
  params: RecedeParams,
  result?: RecedeFrame,
): RecedeFrame;

export function recedeFactors(
  distanceM: number,
  frame: RecedeFrame,
  params: RecedeParams,
  result?: RecedeFactors,
): RecedeFactors;

/** `max(combinedAlphaFloor, clamp(focus, 0, 1) × haze)`. */
export function recededAlpha(
  focus: number,
  haze: number,
  params: RecedeParams,
): number;

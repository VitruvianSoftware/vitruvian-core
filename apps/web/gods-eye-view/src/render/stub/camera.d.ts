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
 * The stub renderer's camera (`camera.js`): the reference camera's poses,
 * views, flights and events in plain maths, which a camera port can be
 * built on.
 */
import type { CameraPort, Ecef, GeoRect, Vec3 } from '../contract/index';

/** The eye in world (ECEF) terms. */
export interface StubEye {
  position: Ecef;
  direction: Vec3;
  up: Vec3;
  right: Vec3;
  /** Vertical field of view, radians. */
  fovy: number;
  aspectRatio: number;
  near: number;
}

export interface StubCamera {
  port: CameraPort;
  /** Ends a flight in progress as cancelled, without announcing a command. */
  endFlight(): void;
  /** One frame's camera steps, run in the contract's order. */
  steps: {
    stepFlight(): void;
    stepChanged(): void;
    stepFollow(): void;
    stepMoveDetection(): void;
  };
  eye(): StubEye;
  /** The reasons camera controls are held for. */
  holds(): string[];
  /** The frame the eye is in, column-major from it to the world. */
  eyeFrame(): Float64Array;
  /** Puts `viewRectangle` on the port. */
  setViewRectangle(fn: () => GeoRect | null): void;
}

export function createStubCamera(options: {
  /** CSS size. */
  viewport: () => { width: number; height: number };
  /** The clock, ms. */
  now: () => number;
  /** Scene time, epoch ms. */
  sceneTime: () => number;
  requestRender: (reason: string) => void;
  report: (error: Error) => void;
  /** Where a drawn item is, `aheadMs` on, for a follow of it. */
  drawnPosition?: (
    item: { set: string; id: string },
    aheadMs: number,
  ) => Ecef | null;
  /** `cameraChangeThreshold` (default true). */
  thresholds?: boolean;
  /** `keepEarthFramed` (default false). */
  framing?: boolean;
}): StubCamera;

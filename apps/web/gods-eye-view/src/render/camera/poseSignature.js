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
 * @module render/camera/poseSignature
 * @description A cheap "did the camera move" key for gating passes that
 * depend on the view: the eye's ECEF position to 10 m and its heading, pitch
 * and roll (radians) to a milliradian. It takes a camera port pose or any
 * `{position, heading, pitch, roll}`, so a renderer's own camera reads the
 * same key.
 */

/**
 * @param {{position: {x: number, y: number, z: number}, heading: number,
 *   pitch: number, roll: number}} pose
 * @returns {string}
 */
export function poseSignature(pose) {
  const p = pose.position;
  return (
    `${Math.round(p.x / 10)}:${Math.round(p.y / 10)}:${Math.round(p.z / 10)}:` +
    `${pose.heading.toFixed(3)}:${pose.pitch.toFixed(3)}:${pose.roll.toFixed(3)}`
  );
}

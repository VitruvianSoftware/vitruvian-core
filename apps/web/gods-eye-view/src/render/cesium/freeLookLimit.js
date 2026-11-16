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
 * @module render/cesium/freeLookLimit
 * @description Keeps the Cesium camera controller's free look to low
 * heights. It writes that controller's own settings, so it lives in the
 * adapter; the application installs it through the scene's viewer hooks
 * (`application.js`).
 */
/**
 * Allow Cesium's free look only below `maxHeight` and return its disposer.
 * Orbit, tilt and zoom stay available at every height. A value other code
 * sets later is kept as the one to allow below that height, and restored on
 * dispose; a `false` written while the camera is above `maxHeight` cannot be
 * told apart from this limit's own write, so dispose restores the earlier
 * value then. `enableLook` gates the Shift+drag binding only: below its trackball
 * height Cesium also turns the camera in place for a drag that starts on the
 * stars. That height is lowered to `maxHeight` too, so above it such a drag
 * orbits the globe, as it does above Cesium's own 7,500 km.
 */
export function installFreeLookHeightLimit(viewer, maxHeight) {
  const scene = viewer?.scene;
  const controller = scene?.screenSpaceCameraController;
  const camera = viewer?.camera;
  if (!controller || !camera || !scene?.preUpdate)
    throw new TypeError('A complete Cesium viewer is required');

  const originalTrackBallHeight = controller.minimumTrackBallHeight;
  const trackBallHeight = Math.min(originalTrackBallHeight, maxHeight);
  controller.minimumTrackBallHeight = trackBallHeight;
  let wanted = controller.enableLook;
  let written;
  const sync = () => {
    if (written !== undefined && controller.enableLook !== written)
      wanted = controller.enableLook;
    const height = camera.positionCartographic?.height;
    written = wanted && !(Number.isFinite(height) && height > maxHeight);
    controller.enableLook = written;
  };
  sync();
  const removeListener = scene.preUpdate.addEventListener(sync);

  let active = true;
  return () => {
    if (!active) return;
    active = false;
    removeListener();
    if (controller.enableLook === written) controller.enableLook = wanted;
    if (controller.minimumTrackBallHeight === trackBallHeight)
      controller.minimumTrackBallHeight = originalTrackBallHeight;
  };
}

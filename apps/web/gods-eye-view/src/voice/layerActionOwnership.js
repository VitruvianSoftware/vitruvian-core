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
 * Observe an explicit request to turn a layer off while a feature action is
 * pending. The visibility-request stream is synchronous, so an OFF owns the
 * action even before the layer's queued lifecycle work settles.
 *
 * @module voice/layerActionOwnership
 */

const EXPLICIT_OFF_ORIGINS = new Set(['user', 'voice', 'tool']);

export function watchExplicitLayerOff(dataManager, layerId, { onOff } = {}) {
  let requested = false;
  const observe = (change) => {
    if (
      change?.layerId === layerId &&
      change.enabled === false &&
      EXPLICIT_OFF_ORIGINS.has(change.origin)
    ) {
      requested = true;
      onOff?.(change);
    }
  };
  const stopRequest =
    dataManager?.subscribeVisibilityRequests?.(observe) || (() => {});
  // Lightweight managers sometimes expose only the settled change stream.
  const stopSettled = dataManager?.subscribe?.(observe) || (() => {});
  return {
    requested: () => requested,
    stop() {
      stopRequest();
      stopSettled();
    },
  };
}

export function displacedLayerResult(dataManager, layerId, action, error) {
  const state = dataManager?.getLayerLifecycleState?.(layerId);
  return {
    ok: false,
    action,
    code: 'DISPLACED',
    cancelled: true,
    layerId,
    requestedEnabled: false,
    error,
    enabled:
      typeof state?.enabled === 'boolean'
        ? state.enabled
        : Boolean(dataManager?.isEnabled?.(layerId)),
    ...(state?.lifecycleState ? { lifecycleState: state.lifecycleState } : {}),
    ...(typeof state?.uncertain === 'boolean'
      ? { lifecycleUncertain: state.uncertain }
      : {}),
  };
}

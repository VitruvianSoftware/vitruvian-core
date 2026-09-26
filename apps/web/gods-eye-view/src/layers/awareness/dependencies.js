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

import { DEPENDENCIES, AIRCRAFT_DEPENDENCIES } from './policy.js';

export function createDependencies({
  state: layerState,
  services,
  parts,
  source,
}) {
  function refreshAfterDeferredDependency(activationId) {
    if (
      !layerState.enabled ||
      layerState.passive ||
      activationId !== layerState.activationId
    )
      return;
    if (layerState.subject) {
      parts.subject.refreshSelectedSubject(true);
      return;
    }
    if (layerState.autoFocusRetryPending) {
      layerState.autoFocusRetryPending = !parts.focus.focusAttentionTarget();
    }
  }

  async function enableDependencies(activationId = layerState.activationId) {
    const aircraftPending = [];
    for (const layerId of DEPENDENCIES) {
      if (!layerState.enabled) return;
      if (!layerState.dataManager) continue;
      const alreadyEnabled =
        layerState.dataManager.isEffectivelyEnabled?.(layerId) ??
        layerState.dataManager.isEnabled(layerId);
      if (alreadyEnabled) continue;
      layerState.ownedDependencies.add(layerId);
      // Each layer serializes its own lifecycle internally. Start them together
      // so a slow or unavailable live feed cannot prevent the remaining context
      // sources from turning on.
      let pending;
      try {
        // Register the ON intent synchronously. If Contacts is turned OFF in the
        // same turn, DataLayerManager then sees OFF as the newest intent and a
        // stale deferred ON cannot resurrect a released dependency.
        pending = Promise.resolve(
          layerState.dataManager.setEnabled(layerId, true),
        );
      } catch (error) {
        pending = Promise.reject(error);
      }
      if (AIRCRAFT_DEPENDENCIES.includes(layerId)) {
        aircraftPending.push(pending);
      } else {
        // Vessels and mapped installations enrich an already usable aircraft
        // context. Their settlement must never hold the Contacts transaction or
        // Cockpit gate open, and the activation token prevents a late result
        // from repainting or refocusing a newer/closed session.
        pending.then(
          () => refreshAfterDeferredDependency(activationId),
          () => refreshAfterDeferredDependency(activationId),
        );
      }
    }
    await Promise.allSettled(aircraftPending);
  }

  function releaseOwnedDependencies(releaseActivationId) {
    const owned = [...layerState.ownedDependencies];
    layerState.ownedDependencies.clear();
    if (!layerState.dataManager || !owned.length) return Promise.resolve();
    return Promise.allSettled(
      owned.map((layerId) => layerState.dataManager.setEnabled(layerId, false)),
    ).then(() => {
      if (
        layerState.enabled &&
        layerState.activationId !== releaseActivationId
      ) {
        return enableDependencies(layerState.activationId);
      }
      return null;
    });
  }

  function activateOperationalContext() {
    const activationId = ++layerState.activationId;
    layerState.autoFocusRetryPending = false;
    const initialTrackedSubject = parts.subject.currentTrackedFlightSubject();
    if (initialTrackedSubject)
      parts.subject.selectSubject(initialTrackedSubject);
    return enableDependencies(activationId)
      .then(() => {
        if (
          !layerState.enabled ||
          layerState.passive ||
          activationId !== layerState.activationId
        )
          return;
        const trackedSubject = parts.subject.currentTrackedFlightSubject();
        if (trackedSubject) {
          parts.subject.selectSubject(trackedSubject);
          return;
        }
        if (layerState.subject) {
          parts.subject.selectSubject(layerState.subject);
          return;
        }
        if (layerState.autoFocusAttempted) return;
        layerState.autoFocusRetryPending = !parts.focus.focusAttentionTarget();
      })
      .catch((error) =>
        console.warn('[Global Context] dependency enable failed', error),
      );
  }
  return {
    refreshAfterDeferredDependency,
    enableDependencies,
    releaseOwnedDependencies,
    activateOperationalContext,
  };
}

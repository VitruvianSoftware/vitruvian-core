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

export function createPresentation({
  state: layerState,
  services,
  parts,
  source,
}) {
  /** Return the deeply immutable healthy catalog generation shared with tuner consumers. */

  function getRadioAcceptedCatalogSnapshot() {
    return layerState._acceptedCatalogSnapshot;
  }

  /** Return an immutable snapshot consumed by the right-rail UI. */

  function getRadioUIState() {
    const visible = parts.queries.visibleStations();
    const selected = parts.queries.selectedStation();
    return Object.freeze({
      enabled: layerState._enabled,
      loading: layerState._loading,
      stale: layerState._stale,
      degraded: layerState._degraded,
      error: layerState._error,
      updatedAt: layerState._updatedAt,
      filter: layerState._filter,
      categories: layerState._categories,
      acceptedCatalogGeneration: layerState._acceptedCatalogSnapshot.generation,
      presentationActive: parts.interaction.radioPresentationAllowed(),
      stationCount: layerState._stations.length,
      filteredCount: visible.length,
      selected,
      selectedIndex: selected
        ? visible.findIndex((station) => station.id === selected.id)
        : -1,
      audioState: layerState._audioState,
      audioError: layerState._audioError,
      playingStationId: layerState._audioStationId,
      volume: layerState._userVolume,
      effectiveVolume:
        layerState._audio?.volume ??
        (layerState._voiceDucked ? 0 : layerState._userVolume),
      voiceDucked: layerState._voiceDucked,
      voiceRestoring: layerState._voiceRestoring,
      tuningActive: layerState._tuningActive,
      tuningStatic: layerState._tuningStatic,
      tuningAwaitingStationId: layerState._tuningAwaitingStationId,
      tuningPreviewStationId: layerState._tuningPreviewId,
      tuningRestoredStationId:
        layerState._cancelledTuningPresentationStation?.id || null,
      tuningCatalogGeneration: layerState._tuningResolutionSnapshot.generation,
      tuningUnavailableStationId: layerState._tuningUnavailableStationId,
    });
  }

  function emitState() {
    const snapshot = getRadioUIState();
    for (const listener of layerState._listeners) {
      try {
        listener(snapshot);
      } catch {
        // A broken consumer must not break playback or rendering.
      }
    }
  }

  /** Subscribe to radio state; the current state is delivered immediately. */

  function subscribeToRadio(listener) {
    if (typeof listener !== 'function') return () => {};
    layerState._listeners.add(listener);
    listener(getRadioUIState());
    return () => layerState._listeners.delete(listener);
  }

  /** Subscribe to explicit playback controls so voice handoffs cannot undo them. */

  function subscribeToRadioPlaybackControls(listener) {
    if (typeof listener !== 'function') return () => {};
    layerState._playbackControlListeners.add(listener);
    return () => layerState._playbackControlListeners.delete(listener);
  }

  function emitPlaybackControl(
    action,
    origin,
    attemptId = layerState._activePlaybackAttempt?.id || null,
  ) {
    const event = { action, origin, attemptId };
    for (const listener of layerState._playbackControlListeners) {
      try {
        listener(event);
      } catch {
        // Playback controls must remain usable if an observer fails.
      }
    }
  }
  return {
    getRadioAcceptedCatalogSnapshot,
    getRadioUIState,
    emitState,
    subscribeToRadio,
    subscribeToRadioPlaybackControls,
    emitPlaybackControl,
  };
}

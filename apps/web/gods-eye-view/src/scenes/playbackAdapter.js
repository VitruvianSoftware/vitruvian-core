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

/** Connect the portable Director runner to the existing scene presentation. */
export function createScenePlaybackAdapter(director, defaultShotDurationSec) {
  let timing;
  let travel;
  return {
    async releaseScene(scene, token) {
      const released = await director._releaseSceneLayers(scene, token);
      if (!token || released) director._loadedSceneId = null;
      return released;
    },
    selectShot({ scene, shot, index, total }) {
      director._selectedSceneId = scene.id;
      director._selectedShotId = shot.id;
      director._renderSceneSelect();
      director._renderShotList();
      director._updateStatus(
        `Running ${index + 1}/${total}: ${scene.title} / ${shot.title}`,
      );
      director._logEvent('shot_start', {
        sceneId: scene.id,
        shotId: shot.id,
        title: shot.title,
        index,
      });
    },
    applyVisual({ shot, token }) {
      return director.styleManager.applyVisualState(
        director._visualStateForShot(shot),
        { isCurrent: () => !token.cancelled && !token.signal?.aborted },
      );
    },
    async applyLayers({ scene, shot, token }) {
      director._setSceneMediaPlayback(scene, shot, token);
      const result = await director._applyLayerStates(
        director._layerStatesForShot(scene, shot),
        token,
      );
      if (
        !token.cancelled &&
        !result.refused.length &&
        !(await director._applyDataPacks(scene, shot, token))
      )
        throw new Error('Data packs unavailable');
      return result;
    },
    travel({ scene, shot, token }) {
      director._loadedSceneId = scene.id;
      const duration = shot.durationSec || defaultShotDurationSec;
      timing = director._startSceneClockTicker(scene, shot, token);
      travel = director._beginShotTravel(scene, shot, duration);
      const flight = director._flyShotCamera(scene, shot, duration, token);
      director._publishShotTravel(scene, shot, travel);
      return flight;
    },
    settle({ scene, shot, token }) {
      director._settleShotLayerStates(scene, shot, token, travel);
    },
    hold({ scene, shot, token }) {
      return director._holdShot(scene, shot, token);
    },
    completeShot({ scene, shot, index }) {
      director._clock.stopSceneTimer();
      director._publishSceneClock(scene, shot, timing.endElapsedSec, {
        running: true,
      });
      director._logEvent('shot_end', {
        sceneId: scene.id,
        shotId: shot.id,
        index,
      });
    },
    complete() {
      director._setProgress(1);
      director._updateStatus('Scene run complete');
      director._logEvent('scene_run_complete', {});
    },
  };
}

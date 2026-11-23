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

import { catalogControlServices } from './catalog.js';
import { StyleManager } from '../ui/composition.js';
import { applyStartView, HOME_START_VIEW, START_VIEW } from '../camera.js';
import { initCockpitCloudEffects } from '../cockpitCloudEffects.js';
import { createViewSky } from '../viewSky.js';
import { findGlobe } from '../render/rendererOf.js';
import { useDisplayStore } from '../ui/stores/display.js';
import { applicationPinia } from '../ui/vueRuntime.js';
import { t } from '../i18n/index.js';

/** Where the camera starts unless a host gives a `startView`. */
export { START_VIEW };

/**
 * Construct the existing controls and camera presentation. `initialShareCode`
 * opens a share code (the `<code>` of `/share/<code>`) at start-up, for a host
 * whose address does not carry one. `localePicker: false` removes the language
 * picker, for a host that offers its own language choice (`switchLocale` from
 * the `./i18n` entry). `startView` is where the camera starts (HOME_VIEW's
 * city by default; a host may pass another); a shared view flies from there.
 * `homeView` is where the title's logo goes back to (with the clock live): the
 * start view unless given, for a host whose `startView` only carries a view
 * across a rebuild.
 * `startLayers` are the layer ids a bare address (one that carries no link)
 * starts with: none by default; a host may pass `['flights', 'satellites']`.
 * `services.cockpitSubjects` adds the application's own first-person subjects
 * to the Cockpit (src/cockpitSubjectProviders.js).
 */
export function createApplicationControls({
  scene: { viewer, mapStackController, operations, viewerDrawsEntity },
  loaderStatus,
  Controls = StyleManager,
  services,
  catalog,
  placeSearch,
  defer,
  initialShareCode = null,
  localePicker = true,
  startView = HOME_START_VIEW,
  homeView = startView,
  startLayers = [],
}) {
  // Every boot starts from the same view, before share restoration flies on.
  applyStartView(viewer, startView);
  // Initialize the style manager (post-processing, HUD, locations, share links)
  const styleManager = new Controls(viewer, {
    services: {
      ...services,
      ...operations.surface.controlServices,
      searchAndFlyTo: operations.searchAndFlyTo,
      pickWorldFromScreen: operations.annotationResolver?.pickWorldFromScreen,
      fetchRegionalBrief: (...args) =>
        operations.requests.regional.getBrief(...args),
      ...catalogControlServices(catalog),
      // Whether an entity is one of the viewer's own; the scene answers it.
      viewerDrawsEntity: viewerDrawsEntity ?? services?.viewerDrawsEntity,
    },
    requestServices: operations.requests,
    mapStackController,
    placeSearch,
    // A share code to open at start-up instead of the page's address.
    initialShareCode,
    localePicker,
    homeView,
    startLayers,
  });
  defer(() => styleManager.orbitController.stop());
  defer(() => styleManager.hud.destroy());
  defer(() => styleManager.dispose());
  // The previous multi-canvas weather compositor remains disabled. Cockpit
  // clouds use a separate, capped low-resolution GPU pass that never attaches
  // Cesium fog or post-process stages and is fully stopped in map mode.
  const weatherEffects = null;
  // Where the renderer draws weather, it draws the cockpit's clouds too.
  const cockpitCloudEffects = findGlobe(viewer)?.weather
    ? null
    : initCockpitCloudEffects(viewer, {
        weatherService: operations.requests.weather,
      });
  defer(() => cockpitCloudEffects?.destroy());
  // The atmosphere, sun lighting, sun, moon, stars and Milky Way the user
  // chooses in the Display panel.
  const viewSky = createViewSky(viewer, {
    store: useDisplayStore(applicationPinia()),
  });
  defer(() => viewSky.destroy());

  loaderStatus.textContent = styleManager.hasShareState
    ? t('Restoring shared view...')
    : t('Loading');

  return { styleManager, weatherEffects, cockpitCloudEffects };
}

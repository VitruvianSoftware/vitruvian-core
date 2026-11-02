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

import { createApp } from 'vue';
import { applicationPinia } from '../vueRuntime.js';
import { applicationI18n } from '../i18n.js';
import WelcomeView from './WelcomeView.vue';
import ContextView from './ContextView.vue';
import LayerPanelsView from './LayerPanelsView.vue';
import CommandDockView from './CommandDockView.vue';
import DisplayControlsView from './DisplayControlsView.vue';
import CockpitView from './CockpitView.vue';
import SceneChromeView from './SceneChromeView.vue';
import ProviderSettingsView from './ProviderSettingsView.vue';
import IntelHudView from './IntelHudView.vue';

/**
 * Application views by name. A page places each one with a host element,
 * `<div class="gev-view" data-gev-view="NAME"></div>` (`display: contents`),
 * where the view's markup belongs.
 */
export const APPLICATION_VIEWS = Object.freeze({
  'provider-settings': ProviderSettingsView,
  'scene-chrome': SceneChromeView,
  cockpit: CockpitView,
  'display-controls': DisplayControlsView,
  'command-dock': CommandDockView,
  'layer-panels': LayerPanelsView,
  context: ContextView,
  welcome: WelcomeView,
  'intel-hud': IntelHudView,
});

const mounted = new WeakMap();

/**
 * Render every application view into its host. Views belong to the page, as
 * their static markup did, so they are unmounted only when a later call omits
 * them; omit views before any control code is wired to them. Call before anything
 * reads or translates the page; repeated calls are harmless.
 * @param {Document} [doc] Page document.
 * @param {{omit?: string[]}} [options] Views this page leaves out; their
 *   hosts are removed, unmounting a view an earlier call rendered.
 */
export function mountApplicationViews(
  doc = globalThis.document,
  { omit = [] } = {},
) {
  for (const name of omit) {
    if (!Object.hasOwn(APPLICATION_VIEWS, name))
      throw new Error(`Unknown application view: ${name}`);
  }
  for (const host of doc?.querySelectorAll?.('[data-gev-view]') ?? []) {
    const name = host.getAttribute('data-gev-view');
    if (omit.includes(name)) {
      mounted.get(host)?.unmount();
      mounted.delete(host);
      host.remove();
      continue;
    }
    if (mounted.has(host)) continue;
    if (!Object.hasOwn(APPLICATION_VIEWS, name))
      throw new Error(`Unknown application view: ${name}`);
    const app = createApp(APPLICATION_VIEWS[name])
      .use(applicationPinia())
      .use(applicationI18n());
    app.mount(host);
    mounted.set(host, app);
  }
}

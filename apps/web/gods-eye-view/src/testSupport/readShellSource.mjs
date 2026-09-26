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

import { ShellFacade } from '../ui/shellFacade.js';
import { AircraftDisplay } from '../ui/aircraftDisplay.js';
import { LayerBindings } from '../ui/layerBindings.js';
import { DisplayBindings } from '../ui/displayBindings.js';
import { readFileSync } from 'node:fs';
import { CockpitCoordinator } from '../ui/cockpitCoordinator.js';
import { LocationNavigation } from '../ui/locationNavigation.js';
import { StyleManager } from '../ui/applicationShell.js';
import { NavigationController } from '../ui/navigationController.js';
import { ShareRestoration } from '../ui/shareRestoration.js';
import { VisualSettings } from '../ui/visualSettings.js';
import { PanelChrome } from '../ui/panelChrome.js';

/** Read the state owners as well as the compatibility/composition facade. */
export function readShellSource() {
  return [
    'locationNavigation',
    'cockpitCoordinator',
    'navigationController',
    'shareRestoration',
    'visualSettings',
    'panelChrome',
    'aircraftDisplay',
    'layerBindings',
    'displayBindings',
    'shellFacade',
    'applicationShell',
  ]
    .map((name) =>
      readFileSync(new URL(`../ui/${name}.js`, import.meta.url), 'utf8'),
    )
    .join('\n');
}

/** Select the implementation owner instead of testing a forwarding facade. */
export function shellMethod(name) {
  for (const owner of [
    NavigationController,
    ShareRestoration,
    VisualSettings,
    PanelChrome,
    LocationNavigation,
    CockpitCoordinator,
    AircraftDisplay,
    LayerBindings,
    DisplayBindings,
    StyleManager,
    ShellFacade,
  ]) {
    const method = Object.getOwnPropertyDescriptor(
      owner.prototype,
      name,
    )?.value;
    if (typeof method === 'function') return method;
  }
  return null;
}

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

import { shouldExpandGlobalContextPanel } from '../rightRailPolicy.js';

export function _initGlobalContextPanel() {
  const contextTabs = [
    this._globalContextFlightsBtn,
    this._globalContextMissionsBtn,
  ].filter(Boolean);
  contextTabs.forEach((tab, index) =>
    this.listen(tab, 'keydown', (event) => {
      let nextIndex = null;
      if (event.key === 'ArrowRight')
        nextIndex = (index + 1) % contextTabs.length;
      else if (event.key === 'ArrowLeft')
        nextIndex = (index - 1 + contextTabs.length) % contextTabs.length;
      else if (event.key === 'Home') nextIndex = 0;
      else if (event.key === 'End') nextIndex = contextTabs.length - 1;
      if (nextIndex === null) return;
      event.preventDefault();
      contextTabs[nextIndex].focus({ preventScroll: true });
      contextTabs[nextIndex].click();
    }),
  );
  this.listen(this._globalContextFlightsBtn, 'click', () => {
    if (
      this.destroyed ||
      this._contextModeChanging ||
      this._clearSelectedLayersPromise
    )
      return;
    const nextMode = this._contextMode === 'flights' ? null : 'flights';
    this._claimContextVisualAuthority();
    void this._runUserFacingContextAction(
      (notificationToken) =>
        this._selectContextMode(nextMode, { notificationToken }),
      'Contacts could not complete the requested transition; try again',
    ).then((succeeded) => {
      if (
        !this.destroyed &&
        nextMode &&
        shouldExpandGlobalContextPanel({
          action: 'contacts',
          explicitUserAction: true,
          succeeded: succeeded === true,
        })
      )
        this.actions.setPanelCollapsed('global-context-panel', false, {
          explicit: true,
        });
    });
  });
  this.listen(this._globalContextMissionsBtn, 'click', () => {
    if (
      this.destroyed ||
      this._contextModeChanging ||
      this._clearSelectedLayersPromise
    )
      return;
    const nextMode =
      this._contextMode === 'space-missions' ? null : 'space-missions';
    this._claimContextVisualAuthority();
    void this._runUserFacingContextAction(
      (notificationToken) =>
        this._selectContextMode(nextMode, { notificationToken }),
      'Space Missions could not complete the requested transition; try again',
    ).then((succeeded) => {
      if (
        !this.destroyed &&
        nextMode &&
        shouldExpandGlobalContextPanel({
          action: 'space-missions',
          explicitUserAction: true,
          succeeded: succeeded === true,
        })
      )
        this.actions.setPanelCollapsed('global-context-panel', false, {
          explicit: true,
        });
    });
  });
  this.listen(this._installationsSearchBtn, 'click', () => {
    if (
      this.destroyed ||
      !this._dataManager?.layers?.has('military-installations')
    )
      return;
    const button = this._installationsSearchBtn;
    if (button.getAttribute('aria-busy') === 'true') return;
    button.setAttribute('aria-disabled', 'true');
    button.setAttribute('aria-busy', 'true');
    void this._runUserFacingContextAction(async (notificationToken) => {
      const enabled = await this._dataManager.setEnabled(
        'military-installations',
        true,
        {
          origin: 'user',
          notificationToken,
        },
      );
      if (
        this.destroyed ||
        enabled === false ||
        !this._dataManager.isEnabled('military-installations')
      )
        return false;
      const searched = await this.installations.searchNearby?.();
      if (this.destroyed || searched === false) return false;
      const stats = this.installations.getStats?.();
      this.showToast(
        stats?.statusMessage ||
          (stats?.status === 'zoom-in'
            ? 'Zoom in to search mapped installations'
            : 'Nearby installations refreshed'),
      );
      return true;
    }, 'Nearby installations could not be refreshed; try again').finally(() => {
      if (this.destroyed) return;
      button.setAttribute('aria-disabled', 'false');
      button.setAttribute('aria-busy', 'false');
    });
  });
}
